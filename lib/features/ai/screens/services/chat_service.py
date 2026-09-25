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
        intent = classify_intent(question)
        collections_needed = determine_required_collections(intent)
        
        # 2. Check Cache
        cached = get_cached_context(uid)
        
        if cached:
            cache_hit = True
            full_data = cached["data"]
            summary = cached["summary"]
        else:
            # Rebuild cache
            rebuild_start = time.time()
            full_data = fetch_user_data(uid) # Try Firestore first
            
            # If Firestore returned empty data and client sent data, use that
            if (not full_data.get("expenses") and not full_data.get("company")) and client_data:
                print("📱 Using client-provided financial data (Firestore unavailable)")
                full_data = client_data
                
            firestore_duration += (time.time() - rebuild_start)
            
            summary = build_business_summary(full_data, currency_symbol)
            set_cached_context(uid, full_data, summary)
            rebuild_duration = time.time() - rebuild_start
            
        # 3. Retrieve relevant specifics based on intent
        retrieved_context = retrieve_relevant_data(intent, summary, full_data, currency_symbol)
        
        # 4. Build Prompt (No Summarization Latency)
        messages = build_prompt(question, summary, retrieved_context, history)
        
        # 5. Call LLM
        answer, groq_latency = call_groq_llm(messages, max_tokens=600)
        
        total_time = time.time() - start_time
        log_chat_request(uid, cache_hit, rebuild_duration, firestore_duration, groq_latency, total_time, True)
        return answer
        
    except Exception as e:
        total_time = time.time() - start_time
        log_chat_request(uid, cache_hit, rebuild_duration, firestore_duration, groq_latency, total_time, False, str(e))
        raise e

def process_chat_message_stream(uid: str, question: str, history: list, client_data: dict = None, currency_symbol: str = "$"):
    start_time = time.time()
    try:
        intent = classify_intent(question)
        collections_needed = determine_required_collections(intent)
        
        cached = get_cached_context(uid)
        if cached:
            full_data = cached["data"]
            summary = cached["summary"]
        else:
            full_data = fetch_user_data(uid)
            if (not full_data.get("expenses") and not full_data.get("company")) and client_data:
                full_data = client_data
            summary = build_business_summary(full_data, currency_symbol)
            set_cached_context(uid, full_data, summary)
            
        retrieved_context = retrieve_relevant_data(intent, summary, full_data, currency_symbol)
        messages = build_prompt(question, summary, retrieved_context, history)
        
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
            timeout=15
        )
        
        for line in response.iter_lines():
            if line:
                yield line.decode('utf-8') + "\n\n"
                
    except Exception as e:
        yield f"data: {{\"error\": \"{str(e)}\"}}\n\n"

