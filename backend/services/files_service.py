"""Server-side proxy for Telegram file storage and Gemini receipt OCR.

The bot token and Gemini key live only on the server (env vars). The app
uploads/downloads through these endpoints with its Firebase ID token, so the
APK never contains either secret.

Ownership: every upload is recorded in `file_owners/{fileId}` with the
uploader's uid; downloads are only served to that uid. Legacy file ids that
predate the proxy are allowed if the caller owns an expense/member/user doc
that references them.
"""

from __future__ import annotations

import base64
import json
import os
import re
import time
from typing import Optional

import requests
from fastapi import HTTPException

from .firestore_service import get_firestore_client

TELEGRAM_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "-1003885930746")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3-flash-preview")

MAX_UPLOAD_BYTES = 20 * 1024 * 1024  # Telegram bot API limit for sendDocument
_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/gif"}
_FILE_ID = re.compile(r"^[A-Za-z0-9_\-]{10,300}$")

# file_id -> (file_path, fetched_at); Telegram file paths are valid ~1h+.
_path_cache: dict[str, tuple[str, float]] = {}
_PATH_TTL = 30 * 60


def _require_telegram():
    if not TELEGRAM_TOKEN:
        raise HTTPException(status_code=503, detail="File storage is not configured.")


def _tg(method: str) -> str:
    return f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/{method}"


# ---------------------------------------------------------------------------
# Ownership
# ---------------------------------------------------------------------------

def _record_owner(file_id: str, uid: str, name: str, mime: str):
    db = get_firestore_client()
    if not db:
        return
    try:
        db.collection("file_owners").document(file_id).set({
            "uid": uid, "name": name, "mime": mime, "createdAt": time.time(),
        })
    except Exception as e:
        print(f"⚠️ [FILES] owner record failed: {type(e).__name__}")


def _owns(file_id: str, uid: str) -> bool:
    db = get_firestore_client()
    if not db:
        # Without Firestore we can't verify; fail closed.
        return False
    try:
        doc = db.collection("file_owners").document(file_id).get()
        if doc.exists:
            return (doc.to_dict() or {}).get("uid") == uid
        # Legacy ids (uploaded before the proxy existed): allow if one of the
        # caller's own docs references this file id.
        from google.cloud.firestore_v1.base_query import FieldFilter
        checks = [
            ("expenses", "AttachmentFileId"),
            ("members", "telegramFileId"),
        ]
        for coll, field in checks:
            q = (db.collection(coll)
                 .where(filter=FieldFilter("uid", "==", uid))
                 .where(filter=FieldFilter(field, "==", file_id))
                 .limit(1).get())
            if q:
                return True
        user = db.collection("users").document(uid).get()
        return bool(user.exists and (user.to_dict() or {}).get("profileImageFileId") == file_id)
    except Exception as e:
        print(f"⚠️ [FILES] ownership check failed: {type(e).__name__}")
        return False


# ---------------------------------------------------------------------------
# Upload / download
# ---------------------------------------------------------------------------

def upload_file(uid: str, data_b64: str, file_name: str, mime: str, as_photo: bool = True) -> dict:
    """Uploads base64 bytes (JSON body; avoids a multipart dependency)."""
    _require_telegram()
    try:
        data = base64.b64decode(data_b64 or "", validate=True)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid file data.")
    if not data:
        raise HTTPException(status_code=400, detail="Empty file.")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File is too large (max 20 MB).")

    name = os.path.basename(file_name or "upload")[:120] or "upload"
    mime = (mime or _guess_type(name))[:100]
    # sendPhoto recompresses and only accepts images; other files are documents.
    is_image = as_photo and mime in _IMAGE_TYPES

    method, field = ("sendPhoto", "photo") if is_image else ("sendDocument", "document")
    try:
        r = requests.post(
            _tg(method),
            data={"chat_id": TELEGRAM_CHAT_ID},
            files={field: (name, data, mime)},
            timeout=60,
        )
    except requests.RequestException as e:
        print(f"🔴 [FILES] upload network error: {type(e).__name__}")
        raise HTTPException(status_code=502, detail="Upload failed. Please try again.")

    body = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
    if r.status_code != 200 or not body.get("ok"):
        print(f"🔴 [FILES] Telegram {method} HTTP {r.status_code}")
        raise HTTPException(status_code=502, detail="Upload failed. Please try again.")

    result = body["result"]
    if is_image:
        photos = result.get("photo") or []
        file_id = photos[-1]["file_id"] if photos else None  # highest quality
    else:
        file_id = (result.get("document") or {}).get("file_id")
    if not file_id:
        raise HTTPException(status_code=502, detail="Upload failed. Please try again.")

    _record_owner(file_id, uid, name, mime)
    return {"fileId": file_id, "fileName": name, "isImage": is_image}


def _file_path(file_id: str) -> str:
    cached = _path_cache.get(file_id)
    if cached and time.time() - cached[1] < _PATH_TTL:
        return cached[0]
    try:
        r = requests.get(_tg("getFile"), params={"file_id": file_id}, timeout=15)
        body = r.json()
    except Exception as e:
        print(f"🔴 [FILES] getFile error: {type(e).__name__}")
        raise HTTPException(status_code=502, detail="Couldn't load the file.")
    path = (body.get("result") or {}).get("file_path") if body.get("ok") else None
    if not path:
        raise HTTPException(status_code=404, detail="File not found or expired.")
    _path_cache[file_id] = (path, time.time())
    return path


def fetch_file(uid: str, file_id: str) -> tuple[bytes, str, str]:
    """Returns (bytes, content_type, file_name) for a file the caller owns."""
    _require_telegram()
    if not _FILE_ID.match(file_id or ""):
        raise HTTPException(status_code=400, detail="Invalid file id.")
    if not _owns(file_id, uid):
        # 404 (not 403) so ids can't be probed.
        raise HTTPException(status_code=404, detail="File not found.")

    path = _file_path(file_id)
    try:
        r = requests.get(f"https://api.telegram.org/file/bot{TELEGRAM_TOKEN}/{path}", timeout=60)
    except requests.RequestException:
        raise HTTPException(status_code=502, detail="Couldn't load the file.")
    if r.status_code != 200:
        _path_cache.pop(file_id, None)
        raise HTTPException(status_code=502, detail="Couldn't load the file.")
    name = os.path.basename(path)
    ctype = r.headers.get("content-type") or _guess_type(name)
    return r.content, ctype, name


def _guess_type(name: str) -> str:
    ext = name.lower().rsplit(".", 1)[-1] if "." in name else ""
    return {
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp",
        "gif": "image/gif", "pdf": "application/pdf", "txt": "text/plain", "csv": "text/csv",
    }.get(ext, "application/octet-stream")


# ---------------------------------------------------------------------------
# Receipt OCR (Gemini Vision)
# ---------------------------------------------------------------------------

_RECEIPT_PROMPT = """Look at this receipt/bill image carefully.
Extract the expense information and return ONLY a valid JSON object — no markdown, no explanation.

{
  "merchant": "business name only",
  "amount": "GRAND TOTAL as plain decimal, e.g. 1139.00 (final total after taxes)",
  "date": "DD/MM/YYYY",
  "category": "one of exactly: marketing | infrastructure | office | software | transport | design | others",
  "description": "one-line summary under 60 chars, no newlines"
}

Rules:
- amount = FINAL/GRAND TOTAL, not subtotal
- merchant = business name only, no address or phone number
- restaurants/cafes/food/drinks -> category "others"
- If a field is not visible, use ""
- Return ONLY the JSON object"""

_FIELDS = ("merchant", "amount", "date", "category", "description")
_CATEGORIES = {"marketing", "infrastructure", "office", "software", "transport", "design", "others"}


def _empty_receipt() -> dict:
    return {"merchant": "", "amount": "", "date": "", "category": "others", "description": ""}


def scan_receipt(image_b64: str, mime: str) -> dict:
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="Receipt scanning is not configured.")
    if mime not in _IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported image type.")
    try:
        raw_len = len(base64.b64decode(image_b64, validate=True))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid image data.")
    if raw_len > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image is too large (max 10 MB).")

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
    payload = {
        "contents": [{"parts": [
            {"inline_data": {"mime_type": mime, "data": image_b64}},
            {"text": _RECEIPT_PROMPT},
        ]}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 500},
    }
    text = ""
    for attempt in range(2):
        try:
            r = requests.post(url, params={"key": GEMINI_API_KEY}, json=payload, timeout=45)
        except requests.RequestException as e:
            print(f"🔴 [OCR] network error: {type(e).__name__}")
            if attempt == 1:
                raise HTTPException(status_code=502, detail="Receipt scan failed. Please try again.")
            time.sleep(2)
            continue
        if r.status_code == 429 and attempt == 0:
            time.sleep(2)
            continue
        if r.status_code != 200:
            print(f"🔴 [OCR] Gemini HTTP {r.status_code}")
            raise HTTPException(status_code=502, detail="Receipt scan failed. Please try again.")
        try:
            text = r.json()["candidates"][0]["content"]["parts"][0]["text"] or ""
        except (KeyError, IndexError, ValueError):
            text = ""
        break

    return _parse_receipt(text)


def _parse_receipt(text: str) -> dict:
    cleaned = re.sub(r"```(?:json)?", "", text or "").strip()
    out = _empty_receipt()
    m = re.search(r"\{[\s\S]*\}", cleaned)
    parsed: Optional[dict] = None
    if m:
        try:
            parsed = json.loads(m.group(0))
        except ValueError:
            parsed = None
    if parsed is None:
        parsed = {}
        for k in _FIELDS:
            fm = re.search(rf'"{k}"\s*:\s*"([^"]*)"', cleaned)
            if fm:
                parsed[k] = fm.group(1)
    for k in _FIELDS:
        v = parsed.get(k)
        if v is not None:
            out[k] = " ".join(str(v).split())[:200]
    if out["category"].lower() not in _CATEGORIES:
        out["category"] = "others"
    else:
        out["category"] = out["category"].lower()
    return out
