import socket
old_getaddrinfo = socket.getaddrinfo
def new_getaddrinfo(*args, **kwargs):
    responses = old_getaddrinfo(*args, **kwargs)
    return [response for response in responses if response[0] == socket.AF_INET]
socket.getaddrinfo = new_getaddrinfo

from dotenv import load_dotenv

# Load env BEFORE importing services: chat_service reads GROQ_API_KEY at import.
load_dotenv()

from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from typing import List, Dict, Any, Optional
import requests
import os
import json
import time

from services.auth_service import verify_token
from services.chat_service import process_chat_message, process_chat_message_stream
from services.cache_service import clear_cache
from services.chat_service import _load_data, _has_data
from services.metrics_service import localize
from services.insights_service import generate_section
from services.files_service import upload_file, fetch_file, scan_receipt
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse, Response

app = FastAPI(title="RunWayX Backend")

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request, exc):
    return JSONResponse(
        status_code=400,
        content={"detail": str(exc)},
    )

# The mobile app doesn't need CORS. Browsers (Flutter web) are allowed only
# from origins listed in ALLOWED_ORIGINS (comma-separated). Auth is a Bearer
# token, not cookies, so credentials are not allowed cross-origin.
_allowed_origins = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)

API_KEY = os.getenv("GROQ_API_KEY")

if not API_KEY:
    print("⚠️  WARNING: GROQ_API_KEY is not configured. AI insights and chat will not work until it is set.")



# ---------------------------
# GROQ CALL
# ---------------------------
def call_llm(prompt, retries=2):
    if not API_KEY:
        print("⚠️  GROQ_API_KEY is not configured. Skipping LLM call.")
        return {
            "error": "AI service is not configured. Please try again later.",
            "code": "llm_not_configured",
        }

    for attempt in range(retries):
        try:
            response = requests.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "openai/gpt-oss-20b",
                    "messages": [
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    "response_format": {"type": "json_object"},
                    "temperature": 0.3,
                    # gpt-oss is a reasoning model: hidden reasoning tokens count
                    # against max_tokens. 800 was truncating longer sections
                    # (keyPoints/burn). Keep reasoning low and leave headroom.
                    "reasoning_effort": "low",
                    "max_tokens": 2048
                },
                timeout=30
            )

            if response.status_code == 429: # Rate Limit
                if attempt == retries - 1:
                    return {
                        "error": "AI service is busy. Please try again in a moment.",
                        "code": "llm_rate_limited",
                    }
                time.sleep(2 ** attempt)
                continue

            if response.status_code == 401:
                # Never leak the raw upstream body; log details server-side only.
                print(f"LLM API auth error (server-side): {response.text}")
                return {
                    "error": "AI service authentication is misconfigured. Please try again later.",
                    "code": "llm_auth_failed",
                }

            if response.status_code != 200:
                print(f"LLM API Error (server-side): {response.text}")
                return {
                    "error": "AI service is temporarily unavailable. Please try again later.",
                    "code": "llm_unavailable",
                }

            content = response.json()["choices"][0]["message"]["content"]
            
            # Clean markdown codeblocks
            content = content.strip()
            if content.startswith("```json"):
                content = content[7:]
            elif content.startswith("```"):
                content = content[3:]
            if content.endswith("```"):
                content = content[:-3]
                
            return json.loads(content.strip())

        except Exception as e:
            if attempt == retries - 1:
                print(f"LLM Parsing Error: {e}")
                return {
                    "error": "AI service is temporarily unavailable. Please try again later.",
                    "code": "llm_unavailable",
                }
            time.sleep(1)


# ---------------------------
# HEALTH CHECK
# ---------------------------
@app.get("/")
def home():
    return {
        "status": "AI backend running"
    }


# Lightweight per-user rate limit (in-memory, per instance) so a single
# account can't exhaust the Groq quota.
_RATE_WINDOW_S = 60
_RATE_MAX = int(os.getenv("AI_RATE_LIMIT_PER_MIN", "30"))
_rate_hits: dict = {}


def rate_limited_user(uid: str = Depends(verify_token)) -> str:
    now = time.time()
    hits = [t for t in _rate_hits.get(uid, []) if now - t < _RATE_WINDOW_S]
    if len(hits) >= _RATE_MAX:
        raise HTTPException(status_code=429, detail="Too many AI requests. Please wait a minute.")
    hits.append(now)
    _rate_hits[uid] = hits
    return uid


# ---------------------------
# MAIN ENDPOINT
# ---------------------------
@app.post("/generate-ai-section")
def generate_ai_section(data: dict, uid: str = Depends(rate_limited_user)):
    section_name = str(data.get("sectionName") or "main")
    currency_symbol = str(data.get("currencySymbol") or "$")[:4]

    # Prefer the backend's own read (full history, all collections); fall back
    # to the snapshot the app sent if Firestore isn't reachable from here.
    full_data, _ = _load_data(uid, data.get("sectionData") or {})
    try:
        tz_offset = max(-720, min(840, int(data.get("tzOffsetMinutes") or 0)))
    except (TypeError, ValueError):
        tz_offset = 0
    return generate_section(section_name, localize(full_data, tz_offset), currency_symbol, call_llm)


# ---------------------------
# CHAT ENDPOINT (REFACTORED)
# ---------------------------
_MAX_HISTORY = 40  # prompt_builder only uses the last 20


class ChatRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=1000)
    sessionId: Optional[str] = None
    # Long chats used to fail with 400 once history passed 60 messages.
    # Keep the most recent ones instead of rejecting the request.
    history: List[Dict[str, Any]] = Field(default_factory=list)
    sectionData: Optional[Dict[str, Any]] = None
    currencySymbol: str = Field("$", max_length=4)
    # Device UTC offset in minutes (IST = 330) so dates and "this month"
    # match the app instead of UTC.
    tzOffsetMinutes: int = Field(0, ge=-720, le=840)

    @field_validator("history", mode="before")
    @classmethod
    def _keep_recent_history(cls, v):
        return v[-_MAX_HISTORY:] if isinstance(v, list) else v


def _chat_context(uid: str, request: ChatRequest):
    """Loads data once. If the backend has nothing and the app didn't attach
    its snapshot, ask the app to resend with it (409) instead of answering
    blind. This lets the app skip uploading its data on every message."""
    loaded = _load_data(uid, request.sectionData)
    if not _has_data(loaded[0]) and request.sectionData is None:
        raise HTTPException(status_code=409, detail="need_client_context")
    return loaded


@app.post("/chat")
def chat_endpoint(request: ChatRequest, uid: str = Depends(rate_limited_user)):
    loaded = _chat_context(uid, request)
    answer = process_chat_message(uid, request.question, request.history, request.sectionData,
                                  request.currencySymbol, request.tzOffsetMinutes, preloaded=loaded)
    return {
        "status": "success",
        "response": answer
    }

@app.post("/chat/stream")
def chat_endpoint_stream(request: ChatRequest, uid: str = Depends(rate_limited_user)):
    loaded = _chat_context(uid, request)
    return StreamingResponse(
        process_chat_message_stream(uid, request.question, request.history, request.sectionData,
                                    request.currencySymbol, request.tzOffsetMinutes, preloaded=loaded),
        media_type="text/event-stream; charset=utf-8"
    )

# ---------------------------
# FILES + RECEIPT OCR (secrets stay server-side)
# ---------------------------
class UploadRequest(BaseModel):
    data: str = Field(..., min_length=4, max_length=28_000_000)  # base64, ~20 MB
    fileName: str = Field("upload", max_length=200)
    mimeType: str = Field("application/octet-stream", max_length=100)
    asPhoto: bool = True


class ScanRequest(BaseModel):
    image: str = Field(..., min_length=4, max_length=14_000_000)  # base64, ~10 MB
    mimeType: str = Field("image/jpeg", max_length=100)


@app.post("/files/upload")
def files_upload(req: UploadRequest, uid: str = Depends(rate_limited_user)):
    return upload_file(uid, req.data, req.fileName, req.mimeType, req.asPhoto)


@app.get("/files/{file_id}")
def files_get(file_id: str, uid: str = Depends(verify_token)):
    content, ctype, name = fetch_file(uid, file_id)
    safe_name = "".join(c for c in name if c.isalnum() or c in "._-")[:100] or "file"
    return Response(
        content=content,
        media_type=ctype,
        headers={
            "Cache-Control": "private, max-age=3600",
            "Content-Disposition": f'inline; filename="{safe_name}"',
            "X-Content-Type-Options": "nosniff",
        },
    )


@app.post("/receipts/scan")
def receipts_scan(req: ScanRequest, uid: str = Depends(rate_limited_user)):
    return scan_receipt(req.image, req.mimeType)


@app.post("/ai/context/invalidate")
def invalidate_ai_context(uid: str = Depends(verify_token)):
    clear_cache(uid)
    return {"status": "success"}