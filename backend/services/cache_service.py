import time
from .logger import log_cache_event
from .firestore_service import get_firestore_client

_cache = {}
CACHE_TTL = 3600 # 1 hour, relying mostly on event-driven invalidation now

def get_cached_context(uid: str):
    db = get_firestore_client()
    if db:
        try:
            doc_ref = db.collection('ai_context_cache').document(uid)
            doc = doc_ref.get()
            if doc.exists:
                cached = doc.to_dict()
                if time.time() < cached.get('expiration_timestamp', 0):
                    return cached
                else:
                    log_cache_event(uid, "expired")
                    doc_ref.delete()
                    return None
            return None
        except Exception as e:
            print(f"⚠️ [FIRESTORE CACHE] Error reading: {e}")
            
    # Fallback to memory
    if uid in _cache:
        cached = _cache[uid]
        if time.time() < cached['expiration_timestamp']:
            return cached
        else:
            log_cache_event(uid, "expired")
            del _cache[uid]
    return None

def set_cached_context(uid: str, full_data: dict, summary: str):
    cached = {
        "version": "1.1",
        "data": full_data,
        "summary": summary,
        "generation_timestamp": time.time(),
        "expiration_timestamp": time.time() + CACHE_TTL
    }
    
    db = get_firestore_client()
    if db:
        try:
            db.collection('ai_context_cache').document(uid).set(cached)
            log_cache_event(uid, "created_firestore")
            return
        except Exception as e:
            print(f"⚠️ [FIRESTORE CACHE] Error writing: {e}")
            
    # Fallback to memory
    _cache[uid] = cached
    log_cache_event(uid, "created_memory")

def clear_cache(uid: str):
    db = get_firestore_client()
    if db:
        try:
            db.collection('ai_context_cache').document(uid).delete()
        except Exception:
            pass
            
    if uid in _cache:
        del _cache[uid]
        
    log_cache_event(uid, "cleared_event_driven")
