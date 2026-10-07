import time
import logging
import json

# Setup structured logger
logger = logging.getLogger("ai_cfo")
logger.setLevel(logging.INFO)
if not logger.handlers:
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    ch.setFormatter(formatter)
    logger.addHandler(ch)

def log_chat_request(uid: str, cache_hit: bool, rebuild_time: float, firestore_time: float, 
                     groq_latency: float, total_time: float, success: bool, error: str = None):
    log_data = {
        "event": "chat_request",
        "uid": uid,
        "cache_hit": cache_hit,
        "rebuild_duration_ms": round(rebuild_time * 1000, 2),
        "firestore_read_duration_ms": round(firestore_time * 1000, 2),
        "groq_latency_ms": round(groq_latency * 1000, 2),
        "total_response_time_ms": round(total_time * 1000, 2),
        "success": success,
    }
    if error:
        log_data["error"] = error
        
    logger.info(json.dumps(log_data))

def log_cache_event(uid: str, event_type: str):
    logger.info(json.dumps({
        "event": "cache_event",
        "uid": uid,
        "action": event_type
    }))
