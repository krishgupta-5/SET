import time
from .logger import log_cache_event

_cache = {}
CACHE_TTL = 3600 # 1 hour, relying mostly on event-driven invalidation now

def get_cached_context(uid: str):
    if uid in _cache:
        cached = _cache[uid]
        if time.time() - cached['expiration_timestamp'] < 0:
            return cached
        else:
            log_cache_event(uid, "expired")
            del _cache[uid]
    return None

def set_cached_context(uid: str, full_data: dict, summary: str):
    _cache[uid] = {
        "version": "1.1",
        "data": full_data,
        "summary": summary,
        "generation_timestamp": time.time(),
        "expiration_timestamp": time.time() + CACHE_TTL
    }
    log_cache_event(uid, "created")

def clear_cache(uid: str):
    if uid in _cache:
        del _cache[uid]
        log_cache_event(uid, "cleared_event_driven")
