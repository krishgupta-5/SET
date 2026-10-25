"""Tests for the file/OCR proxy and recurring stop dates. Run: venv/bin/python -m pytest tests -q"""
import base64
import os
import sys
from datetime import datetime

import pytest
from fastapi import HTTPException

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import files_service as fs  # noqa: E402
from services import metrics_service as ms  # noqa: E402


# ---------------- recurring stop date ----------------

def test_recurring_end_date_stops_expansion():
    occ = ms.expand_expenses([{
        "Amount": 10, "Date": datetime(2026, 7, 1).isoformat(), "Type": "recurring",
        "recurrenceFrequency": "monthly",
        "recurringEndDate": datetime(2026, 9, 15).isoformat(),
    }], until=datetime(2027, 1, 1))
    # Jul 1, Aug 1, Sep 1 — nothing after the stop date.
    assert [o["_date"].month for o in occ] == [7, 8, 9]


def test_stop_date_on_charge_day_keeps_that_charge():
    occ = ms.expand_expenses([{
        "Amount": 10, "Date": datetime(2026, 7, 1).isoformat(), "Type": "recurring",
        "recurringEndDate": datetime(2026, 8, 1).isoformat(),
    }], until=datetime(2027, 1, 1))
    assert len(occ) == 2


# ---------------- receipt parsing ----------------

def test_parse_receipt_json_and_category_normalised():
    out = fs._parse_receipt('```json\n{"merchant":"Cafe X","amount":"120.50","date":"01/10/2026",'
                            '"category":"Food","description":"Lunch"}\n```')
    assert out["merchant"] == "Cafe X"
    assert out["amount"] == "120.50"
    assert out["category"] == "others"  # not an allowed category


def test_parse_receipt_truncated_json_falls_back_to_regex():
    out = fs._parse_receipt('{"merchant": "Uber", "amount": "300", "category": "transport", "descr')
    assert out["merchant"] == "Uber"
    assert out["category"] == "transport"


def test_parse_receipt_garbage_returns_empty():
    assert fs._parse_receipt("no json here") == fs._empty_receipt()


# ---------------- upload / download guards ----------------

def test_upload_requires_server_token(monkeypatch):
    monkeypatch.setattr(fs, "TELEGRAM_TOKEN", None)
    with pytest.raises(HTTPException) as e:
        fs.upload_file("u1", base64.b64encode(b"x").decode(), "a.jpg", "image/jpeg")
    assert e.value.status_code == 503


def test_upload_rejects_bad_base64(monkeypatch):
    monkeypatch.setattr(fs, "TELEGRAM_TOKEN", "t")
    with pytest.raises(HTTPException) as e:
        fs.upload_file("u1", "not base64!!", "a.jpg", "image/jpeg")
    assert e.value.status_code == 400


def test_upload_rejects_oversize(monkeypatch):
    monkeypatch.setattr(fs, "TELEGRAM_TOKEN", "t")
    monkeypatch.setattr(fs, "MAX_UPLOAD_BYTES", 4)
    with pytest.raises(HTTPException) as e:
        fs.upload_file("u1", base64.b64encode(b"12345").decode(), "a.jpg", "image/jpeg")
    assert e.value.status_code == 413


def test_upload_records_owner_and_picks_best_photo(monkeypatch):
    monkeypatch.setattr(fs, "TELEGRAM_TOKEN", "t")
    owners = {}
    monkeypatch.setattr(fs, "_record_owner", lambda fid, uid, n, m: owners.update({fid: uid}))

    class R:
        status_code = 200
        headers = {"content-type": "application/json"}

        def json(self):
            return {"ok": True, "result": {"photo": [{"file_id": "small_id_123"}, {"file_id": "large_id_456"}]}}

    monkeypatch.setattr(fs.requests, "post", lambda *a, **k: R())
    out = fs.upload_file("u1", base64.b64encode(b"img").decode(), "a.jpg", "image/jpeg")
    assert out["fileId"] == "large_id_456" and out["isImage"] is True
    assert owners == {"large_id_456": "u1"}


def test_fetch_rejects_invalid_id(monkeypatch):
    monkeypatch.setattr(fs, "TELEGRAM_TOKEN", "t")
    with pytest.raises(HTTPException) as e:
        fs.fetch_file("u1", "../etc/passwd")
    assert e.value.status_code == 400


def test_fetch_hides_files_owned_by_others(monkeypatch):
    monkeypatch.setattr(fs, "TELEGRAM_TOKEN", "t")
    monkeypatch.setattr(fs, "_owns", lambda fid, uid: False)
    with pytest.raises(HTTPException) as e:
        fs.fetch_file("attacker", "AgACAgUAAxkBAAIB_valid_looking")
    assert e.value.status_code == 404  # 404, not 403: ids can't be probed


def test_scan_requires_server_key(monkeypatch):
    monkeypatch.setattr(fs, "GEMINI_API_KEY", None)
    with pytest.raises(HTTPException) as e:
        fs.scan_receipt(base64.b64encode(b"x").decode(), "image/jpeg")
    assert e.value.status_code == 503


def test_scan_rejects_non_image(monkeypatch):
    monkeypatch.setattr(fs, "GEMINI_API_KEY", "k")
    with pytest.raises(HTTPException) as e:
        fs.scan_receipt(base64.b64encode(b"x").decode(), "application/pdf")
    assert e.value.status_code == 400


def test_new_routes_registered_and_auth_required(monkeypatch):
    from fastapi.testclient import TestClient
    from services import auth_service
    monkeypatch.setattr(auth_service, "initialize_firebase", lambda: None)
    import main  # load_dotenv() may set DEBUG_MODE from a local .env
    monkeypatch.delenv("DEBUG_MODE", raising=False)
    paths = {r.path for r in main.app.routes}
    assert {"/files/upload", "/files/{file_id}", "/receipts/scan"} <= paths
    client = TestClient(main.app)
    assert client.get("/files/somefileid123").status_code == 401
    assert client.post("/receipts/scan", json={"image": "abcd"}).status_code == 401
