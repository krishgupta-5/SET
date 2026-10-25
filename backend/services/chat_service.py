import json
import os
import time
import requests
from fastapi import HTTPException
from .firestore_service import fetch_user_data
from .context_builder import build_business_summary
from .cache_service import get_cached_context, set_cached_context
from .retriever_service import retrieve_relevant_data
from .intent_classifier import classify_intent
from .prompt_builder import build_prompt
from .logger import log_chat_request

GROQ_API_KEY = os.getenv("GROQ_API_KEY")
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
MODEL = "openai/gpt-oss-20b"


def _has_data(d: dict) -> bool:
    return bool(d and (d.get("expenses") or d.get("company") or d.get("members")))


def _load_data(uid: str, client_data: dict):
    """Returns (full_data, cache_hit).

    Order: cached raw data -> backend Firestore read -> app-provided snapshot.
    Only the raw data is cached; the summary is rebuilt on every request so
    the date ("this month") and currency are always current. Empty contexts
    are never cached.
    """
    cached = get_cached_context(uid)
    if cached and _has_data(cached.get("data", {})):
        return cached["data"], True

    full_data = fetch_user_data(uid)
    if not _has_data(full_data) and _has_data(client_data or {}):
        print("📱 Using client-provided financial data (backend Firestore returned nothing)")
        full_data = client_data

    if _has_data(full_data):
        set_cached_context(uid, full_data, "")
    return full_data, False


def _build_messages(uid, question, history, client_data, currency_symbol):
    intent = classify_intent(question)
    full_data, cache_hit = _load_data(uid, client_data)
    summary = build_business_summary(full_data, currency_symbol)
    retrieved = retrieve_relevant_data(intent, summary, full_data, currency_symbol)
    messages = build_prompt(question, summary, retrieved, history, currency_symbol)
    print(f"🔵 [CHAT] intent={intent} cache_hit={cache_hit} messages={len(messages)}")
    return messages, cache_hit


def _payload(messages, stream=False):
    return {
        "model": MODEL,
        "messages": messages,
        "temperature": 0.3,
        "reasoning_effort": "low",
        "max_tokens": 2048,
        **({"stream": True} if stream else {}),
    }


def _headers():
    return {"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"}


def call_groq_llm(messages: list, max_tokens: int = 1024):
    start_time = time.time()
    if not GROQ_API_KEY:
        raise HTTPException(status_code=503, detail="AI service is not configured. Please try again later.")
    try:
        body = _payload(messages)
        body["max_tokens"] = max_tokens
        response = requests.post(GROQ_URL, headers=_headers(), json=body, timeout=30)
        if response.status_code == 429:
            raise HTTPException(status_code=429, detail="AI service is busy. Please try again in a moment.")
        if response.status_code != 200:
            print(f"Groq API error (server-side): HTTP {response.status_code}")
            raise HTTPException(status_code=502, detail="AI service is temporarily unavailable. Please try again later.")
        data = response.json()
        return data["choices"][0]["message"]["content"], time.time() - start_time
    except requests.exceptions.Timeout:
        raise HTTPException(status_code=504, detail="AI service timed out. Please try again.")
    except requests.exceptions.RequestException as e:
        print(f"Groq request failed: {type(e).__name__}")
        raise HTTPException(status_code=503, detail="AI service is temporarily unavailable. Please try again later.")


def process_chat_message(uid: str, question: str, history: list, client_data: dict = None, currency_symbol: str = "$"):
    start_time = time.time()
    cache_hit = False
    groq_latency = 0.0
    try:
        messages, cache_hit = _build_messages(uid, question, history, client_data, currency_symbol)
        build_time = time.time() - start_time
        answer, groq_latency = call_groq_llm(messages, max_tokens=2048)
        log_chat_request(uid, cache_hit, build_time, build_time, groq_latency, time.time() - start_time, True)
        return answer
    except Exception as e:
        log_chat_request(uid, cache_hit, 0, 0, groq_latency, time.time() - start_time, False, type(e).__name__)
        raise


def _sse_error(message: str) -> str:
    # json.dumps escapes quotes/newlines so the client can always parse it.
    return f"data: {json.dumps({'error': message})}\n\n"


def process_chat_message_stream(uid: str, question: str, history: list, client_data: dict = None, currency_symbol: str = "$"):
    start_time = time.time()
    try:
        if not GROQ_API_KEY:
            yield _sse_error("AI service is not configured. Please try again later.")
            return

        messages, cache_hit = _build_messages(uid, question, history, client_data, currency_symbol)

        with requests.post(
            GROQ_URL, headers=_headers(), json=_payload(messages, stream=True),
            stream=True, timeout=(10, 60),
        ) as response:
            if response.status_code == 429:
                yield _sse_error("AI service is busy. Please try again in a moment.")
                return
            if response.status_code != 200:
                print(f"🔴 [STREAM] Groq error (server-side): HTTP {response.status_code}")
                yield _sse_error("AI service is temporarily unavailable. Please try again later.")
                return

            chunks = 0
            for line in response.iter_lines(decode_unicode=True):
                if not line or not line.startswith("data:"):
                    continue
                chunks += 1
                yield line + "\n\n"
        print(f"🟢 [STREAM] done: {chunks} chunks in {time.time() - start_time:.2f}s (cache_hit={cache_hit})")

    except requests.exceptions.Timeout:
        yield _sse_error("AI service timed out. Please try again.")
    except Exception as e:
        # Log the type only; never send internal exception text to the client.
        print(f"🔴 [STREAM] error: {type(e).__name__}")
        yield _sse_error("Something went wrong while generating a reply. Please try again.")
