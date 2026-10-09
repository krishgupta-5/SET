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

def call_groq_llm(messages: list, max_tokens: int = 1024):
    start_time = time.time()
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
                "max_tokens": max_tokens
            },
            timeout=15
        )
        
        if response.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Groq API Error: {response.text}")
            
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
        
        # 2. Check Cache
        cached = get_cached_context(uid)
        
        if cached:
            cache_hit = True
            full_data = cached["data"]
            summary = cached["summary"]
            print(f"🔵 [CHAT] Cache HIT")
        else:
            print(f"🔵 [CHAT] Cache MISS - fetching from Firestore...")
            # Rebuild cache
            rebuild_start = time.time()
            full_data = fetch_user_data(uid) # Try Firestore first
            print(f"🔵 [CHAT] Firestore fetch complete in {time.time() - rebuild_start:.2f}s")
            
            # If Firestore returned empty data and client sent data, use that
            if (not full_data.get("expenses") and not full_data.get("company")) and client_data:
                print("📱 Using client-provided financial data (Firestore unavailable)")
                full_data = client_data
                
            firestore_duration += (time.time() - rebuild_start)
            
            summary = build_business_summary(full_data, currency_symbol)
            set_cached_context(uid, full_data, summary)
            rebuild_duration = time.time() - rebuild_start
            
        # 3. Retrieve relevant specifics based on intent
        print(f"🔵 [CHAT] Retrieving relevant data...")
        retrieved_context = retrieve_relevant_data(intent, summary, full_data, currency_symbol)
        
        # 4. Build Prompt (No Summarization Latency)
        print(f"🔵 [CHAT] Building prompt...")
        messages = build_prompt(question, summary, retrieved_context, history, currency_symbol)
        print(f"🔵 [CHAT] Prompt built with {len(messages)} messages. Calling Groq LLM...")
        
        # 5. Call LLM
        answer, groq_latency = call_groq_llm(messages, max_tokens=600)
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
        
        cached = get_cached_context(uid)
        if cached:
            full_data = cached["data"]
            summary = cached["summary"]
            print(f"🟢 [STREAM] Cache HIT")
        else:
            print(f"🟢 [STREAM] Cache MISS - fetching Firestore...")
            fs_start = time.time()
            full_data = fetch_user_data(uid)
            print(f"🟢 [STREAM] Firestore fetch took {time.time() - fs_start:.2f}s")
            if (not full_data.get("expenses") and not full_data.get("company")) and client_data:
                print(f"🟢 [STREAM] Using client data fallback")
                full_data = client_data
            summary = build_business_summary(full_data, currency_symbol)
            set_cached_context(uid, full_data, summary)
            
        retrieved_context = retrieve_relevant_data(intent, summary, full_data, currency_symbol)
        messages = build_prompt(question, summary, retrieved_context, history, currency_symbol)
        print(f"🟢 [STREAM] Prompt built ({len(messages)} messages). Calling Groq (streaming)...")
        
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
                "max_tokens": 600,
                "stream": True
            },
            stream=True,
            timeout=30
        )
        
        print(f"🟢 [STREAM] Groq responded with status: {response.status_code}")
        
        if response.status_code != 200:
            error_text = response.text
            print(f"🔴 [STREAM] Groq API Error: {error_text}")
            yield f'data: {{"error": "Groq API Error ({response.status_code}): {error_text}"}}\n\n'
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

