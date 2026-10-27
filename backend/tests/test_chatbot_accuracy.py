"""Regression tests for chatbot accuracy bugs found in the audit."""
import os
import sys
from datetime import datetime, timedelta, timezone

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import metrics_service as ms  # noqa: E402
from services.context_builder import build_business_summary  # noqa: E402
from services.intent_classifier import classify_intent  # noqa: E402
from services.retriever_service import retrieve_relevant_data  # noqa: E402

IST = timezone(timedelta(hours=5, minutes=30))
NOW = datetime(2026, 10, 27, 12)


def salary_payment(month, mid="m1", amount=50000):
    # Exactly what ExpenseService.recordSalaryPayment writes.
    return {"Title": "Salary", "Amount": amount, "Category": "salary", "Type": "recurring",
            "ExpenseType": "member", "memberId": mid, "Date": datetime(2026, month, 5)}


# --- 1. Salary payments are one-off, not a repeating series -----------------

def test_monthly_salary_payments_are_not_double_counted():
    s = ms.compute_snapshot({
        "company": {"Funding": 1_000_000},
        "members": [{"id": "m1", "monthlyCost": 50000, "status": "Active"}],
        "expenses": [salary_payment(8), salary_payment(9), salary_payment(10)],
    }, now=NOW)
    assert s["total_spent"] == 150000
    assert s["monthly_totals"] == {"2026-08": 50000, "2026-09": 50000, "2026-10": 50000}
    assert s["monthly_burn"] == 50000          # paid this month → no unpaid payroll
    assert s["unpaid_payroll_this_month"] == 0


def test_unpaid_salary_still_counts_toward_burn():
    s = ms.compute_snapshot({
        "company": {"Funding": 1_000_000},
        "members": [{"id": "m1", "monthlyCost": 50000, "status": "Active"}],
        "expenses": [salary_payment(9)],       # September paid, October not yet
    }, now=NOW)
    assert s["total_spent"] == 50000
    assert s["unpaid_payroll_this_month"] == 50000


def test_user_created_recurring_salary_still_repeats():
    # Added from "Add expense" with a frequency: a genuine schedule.
    occ = ms.expand_expenses([{**salary_payment(8), "recurrenceFrequency": "monthly"}], until=NOW)
    assert len(occ) == 3


# --- 2. Timezone ------------------------------------------------------------

def test_ist_midnight_date_stays_in_its_month():
    data = ms.localize({"company": {"Funding": 100000}, "expenses": [
        {"Title": "Rent", "Amount": 20000, "Type": "one_time", "Date": datetime(2026, 10, 1, tzinfo=IST)},
    ]}, 330)
    s = ms.compute_snapshot(data, now=NOW)
    assert s["monthly_totals"] == {"2026-10": 20000}
    assert s["recent_expenses"][0]["date"] == "01 Oct 2026"


def test_utc_iso_string_from_app_fallback_is_localized():
    # Client fallback now sends UTC ISO strings (toUtc().toIso8601String()).
    data = ms.localize({"expenses": [{"Amount": 1, "Date": "2026-09-30T18:30:00.000Z"}]}, 330)
    assert data["expenses"][0]["Date"] == datetime(2026, 10, 1)


def test_local_now_uses_offset():
    data = ms.localize({}, 330)
    diff = ms.local_now(data) - datetime.now(timezone.utc).replace(tzinfo=None)
    assert abs(diff.total_seconds() - 330 * 60) < 5


# --- 4. Two different "this month" numbers ----------------------------------

def test_spent_so_far_vs_burn_are_labelled():
    data = {"company": {"Funding": 100000}, "expenses": [
        {"Title": "Coffee", "Amount": 500, "Category": "food", "Date": datetime(2026, 10, 3)},
        {"Title": "Figma", "Amount": 3000, "Type": "subscription", "Category": "software",
         "recurrenceFrequency": "monthly", "Date": datetime(2026, 9, 30)},
    ]}
    s = ms.compute_snapshot(data, now=datetime(2026, 10, 10))
    assert s["current_month_spent_to_date"] == 500
    text = build_business_summary(data, "₹", s)
    assert "Spent so far this month (already paid, up to today): ₹500.00" in text
    assert "full month incl. charges still due): ₹3,500.00" in text


def test_month_by_category_breakdown_in_summary():
    data = {"company": {"Funding": 100000}, "expenses": [
        {"Amount": 700, "Category": "marketing", "Date": datetime(2026, 8, 3)},
        {"Amount": 300, "Category": "marketing", "Date": datetime(2026, 8, 20)},
        {"Amount": 200, "Category": "office", "Date": datetime(2026, 8, 21)},
    ]}
    text = build_business_summary(data, "₹", ms.compute_snapshot(data, now=NOW))
    assert "- August 2026: ₹1,200.00 (marketing ₹1,000.00, office ₹200.00)" in text


def test_emis_are_listed():
    data = {"company": {"Funding": 100000}, "expenses": [
        {"id": "e1", "Title": "EMI: HDFC Loan Repayment", "Amount": 5000, "Type": "recurring",
         "recurrenceFrequency": "monthly", "recurringTenureMonths": 12, "isEmiRepayment": True,
         "Date": datetime(2026, 8, 1)},
    ]}
    text = build_business_summary(data, "₹", ms.compute_snapshot(data, now=NOW))
    assert "EMI: HDFC Loan Repayment: ₹5,000.00/month (tenure 12 months, 3 paid so far)" in text


# --- 5. Intent gaps ---------------------------------------------------------

@pytest.mark.parametrize("q,intent", [
    ("kitna paisa bacha hai", "Cash Flow"),
    ("mera kharcha kitna hua is mahine", "Expense Optimization"),
    ("how is my app doing", "Financial Health"),
    ("how's the business", "Financial Health"),
    ("whats my runaway", "Runway"),
    ("brun rate?", "Burn Rate"),
    ("what are my emis", "Cash Flow"),
    ("list my funding rounds", "Investment"),
    ("where is my money going", "Expense Optimization"),
    ("how much salary did i pay in september", "Payroll"),
    ("how much tax do i owe", "General Startup Advice"),
    ("how much do we pay for notion", "Subscriptions"),
])
def test_intent_handles_real_phrasings(q, intent):
    assert classify_intent(q) == intent


def test_unknown_intent_still_gets_transactions():
    data = {"expenses": [{"Title": "Chai", "Amount": 50, "Date": datetime(2020, 1, 1)}]}
    out = retrieve_relevant_data("Unknown", "", data, "₹")
    assert "Chai: ₹50.00" in out


def test_payroll_intent_gets_salary_payments():
    data = {"members": [{"id": "m1", "fullName": "A", "monthlyCost": "50,000"}],
            "expenses": [salary_payment(9), {"Title": "Ads", "Amount": 9, "Category": "marketing",
                                              "Date": datetime(2026, 9, 1)}]}
    out = retrieve_relevant_data("Payroll", "", data, "₹")
    assert "Salary payments recorded" in out and "05 Sep 2026" in out
    assert "Ads" not in out
    assert "₹50,000.00/mo" in out


# --- 3 & 8. Request handling ------------------------------------------------

@pytest.fixture
def client(monkeypatch):
    from fastapi.testclient import TestClient
    import main
    main.app.dependency_overrides[main.rate_limited_user] = lambda: "u1"
    seen = {}

    def fake_stream(uid, q, history, client_data, cs, tz, preloaded=None):
        seen.update(history=history, tz=tz, preloaded=preloaded)
        yield "data: [DONE]\n\n"

    monkeypatch.setattr(main, "process_chat_message_stream", fake_stream)
    yield TestClient(main.app), seen, main
    main.app.dependency_overrides.clear()


def test_long_history_is_trimmed_not_rejected(client, monkeypatch):
    c, seen, main = client
    monkeypatch.setattr(main, "_load_data", lambda uid, cd: ({"company": {"x": 1}}, True))
    history = [{"role": "user", "text": str(i)} for i in range(120)]
    r = c.post("/chat/stream", json={"question": "hi", "history": history, "tzOffsetMinutes": 330})
    assert r.status_code == 200
    assert len(seen["history"]) == 40 and seen["history"][-1]["text"] == "119"
    assert seen["tz"] == 330


def test_backend_without_data_asks_app_for_snapshot(client, monkeypatch):
    c, seen, main = client
    monkeypatch.setattr(main, "_load_data", lambda uid, cd: (cd or {}, False))
    r = c.post("/chat/stream", json={"question": "hi"})
    assert r.status_code == 409 and r.json()["detail"] == "need_client_context"
    # Retry with the snapshot attached (even an empty one) is answered.
    r = c.post("/chat/stream", json={"question": "hi", "sectionData": {}})
    assert r.status_code == 200


def test_bad_tz_offset_rejected(client):
    c, _, _ = client
    assert c.post("/chat/stream", json={"question": "hi", "tzOffsetMinutes": 5000}).status_code == 400
