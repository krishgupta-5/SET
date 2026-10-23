import os
import time
import requests
from fastapi import HTTPException
from .firestore_service import fetch_user_data
from .context_builder import build_business_summary
from .cache_service import get_cached_context, set_cached_context
from .retriever_service import retrieve_relevant_data, determine_required_collections
from .intent_classifier import classify_intent
from .prompt_builder import build_prompt
from .logger import log_chat_request

GROQ_API_KEY = os.getenv("GROQ_API_KEY")


def _has_data(d: dict) -> bool:
    return bool(d and (d.get("expenses") or d.get("company") or d.get("members")))


def _load_context(uid: str, client_data: dict, currency_symbol: str):
    """Returns (full_data, summary, cache_hit).

    Prefers cached context, then the backend's own Firestore read, then the
    snapshot the app sends. Empty contexts are never cached, so a transient
    Firestore failure can't leave the chatbot blind for an hour.
    """
    cached = get_cached_context(uid)
    if cached and _has_data(cached.get("data", {})):
        return cached["data"], cached["summary"], True

    full_data = fetch_user_data(uid)
    if not _has_data(full_data) and _has_data(client_data or {}):
        print("📱 Using client-provided financial data (backend Firestore returned nothing)")
        full_data = client_data

    summary = build_business_summary(full_data, currency_symbol)
    if _has_data(full_data):
        set_cached_context(uid, full_data, summary)
    return full_data, summary, False

def call_groq_llm(messages: list, max_tokens: int = 1024):
    start_time = time.time()
    if not GROQ_API_KEY:
        print("⚠️  GROQ_API_KEY is not configured. Skipping Groq call.")
        raise HTTPException(status_code=503, detail="AI service is not configured. Please try again later.")
    try:
        response = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {GROQ_API_KEY}",
                "Content-Type": "application/json"
            },
            json={
                "model": "openai/gpt-oss-20b",
                "messages": messages,
                "temperature": 0.3,
                "reasoning_effort": "low",
                "max_tokens": max_tokens
            },
            timeout=15
        )
        
        if response.status_code != 200:
            # Log details server-side only; never leak the raw upstream body to clients.
            print(f"Groq API Error (server-side): {response.text}")
            raise HTTPException(status_code=502, detail="AI service is temporarily unavailable. Please try again later.")
            
        data = response.json()
        latency = time.time() - start_time
        return data["choices"][0]["message"]["content"], latency
    except requests.exceptions.Timeout:
        raise HTTPException(status_code=504, detail="LLM request timed out.")
    except requests.exceptions.RequestException as e:
        raise HTTPException(status_code=503, detail=f"LLM Service Unavailable: {str(e)}")


def process_chat_message(uid: str, question: str, history: list, client_data: dict = None, currency_symbol: str = "$"):
    start_time = time.time()
    cache_hit = False
    rebuild_duration = 0.0
    firestore_duration = 0.0
    groq_latency = 0.0
    
    try:
        # 1. Intent Classification
        print(f"\n🔵 [CHAT] Processing message for UID: {uid}")
        print(f"🔵 [CHAT] Question: {question}")
        intent = classify_intent(question)
        print(f"🔵 [CHAT] Intent classified: {intent}")
        collections_needed = determine_required_collections(intent)
        print(f"🔵 [CHAT] Collections needed: {collections_needed}")
        
        # 2. Load context (cache -> Firestore -> client snapshot)
        rebuild_start = time.time()
        full_data, summary, cache_hit = _load_context(uid, client_data, currency_symbol)
        if not cache_hit:
            rebuild_duration = firestore_duration = time.time() - rebuild_start
        print(f"🔵 [CHAT] Context loaded (cache_hit={cache_hit})")
            
        # 3. Retrieve relevant specifics based on intent
        print(f"🔵 [CHAT] Retrieving relevant data...")
        retrieved_context = retrieve_relevant_data(intent, summary, full_data, currency_symbol)
        
        # 4. Build Prompt (No Summarization Latency)
        print(f"🔵 [CHAT] Building prompt...")
        messages = build_prompt(question, summary, retrieved_context, history, currency_symbol)
        print(f"🔵 [CHAT] Prompt built with {len(messages)} messages. Calling Groq LLM...")
        
        # 5. Call LLM
        answer, groq_latency = call_groq_llm(messages, max_tokens=2048)
        print(f"🔵 [CHAT] Groq responded in {groq_latency:.2f}s")
        
        total_time = time.time() - start_time
        log_chat_request(uid, cache_hit, rebuild_duration, firestore_duration, groq_latency, total_time, True)
        return answer
        
    except Exception as e:
        print(f"🔴 [CHAT] ERROR: {type(e).__name__}: {e}")
        total_time = time.time() - start_time
        log_chat_request(uid, cache_hit, rebuild_duration, firestore_duration, groq_latency, total_time, False, str(e))
        raise e

def process_chat_message_stream(uid: str, question: str, history: list, client_data: dict = None, currency_symbol: str = "$"):
    start_time = time.time()
    try:
        print(f"\n🟢 [STREAM] Processing stream for UID: {uid}")
        print(f"🟢 [STREAM] Question: {question}")
        intent = classify_intent(question)
        print(f"🟢 [STREAM] Intent: {intent}")
        collections_needed = determine_required_collections(intent)
        
        full_data, summary, cache_hit = _load_context(uid, client_data, currency_symbol)
        print(f"🟢 [STREAM] Context loaded (cache_hit={cache_hit})")
            
        retrieved_context = retrieve_relevant_data(intent, summary, full_data, currency_symbol)
        messages = build_prompt(question, summary, retrieved_context, history, currency_symbol)
        print(f"🟢 [STREAM] Prompt built ({len(messages)} messages). Calling Groq (streaming)...")
        
        if not GROQ_API_KEY:
            print("⚠️  GROQ_API_KEY is not configured. Skipping stream call.")
            yield 'data: {"error": "AI service is not configured. Please try again later."}\n\n'
            return

        response = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {GROQ_API_KEY}",
                "Content-Type": "application/json"
            },
            json={
                "model": "openai/gpt-oss-20b",
                "messages": messages,
                "temperature": 0.3,
                "reasoning_effort": "low",
                "max_tokens": 2048,
                "stream": True
            },
            stream=True,
            timeout=30
        )
        
        print(f"🟢 [STREAM] Groq responded with status: {response.status_code}")
        
        if response.status_code != 200:
            print(f"🔴 [STREAM] Groq API Error (server-side): {response.text}")
            yield 'data: {"error": "AI service is temporarily unavailable. Please try again later."}\n\n'
            return
        
        chunk_count = 0
        for line in response.iter_lines():
            if line:
                chunk_count += 1
                decoded = line.decode('utf-8')
                if chunk_count <= 3:
                    print(f"🟢 [STREAM] Chunk {chunk_count}: {decoded[:100]}")
                yield decoded + "\n\n"
        
        print(f"🟢 [STREAM] Done. Total chunks: {chunk_count}, took {time.time() - start_time:.2f}s")
                
    except Exception as e:
        print(f"🔴 [STREAM] ERROR: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        yield f"data: {{\"error\": \"{str(e)}\"}}\n\n"

