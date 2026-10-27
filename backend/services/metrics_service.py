"""Single source of truth for financial metrics on the backend.

Mirrors the app's `FinancialCalculator.compute` (lib/services/financial_calculator.dart)
so the chatbot and AI Insights see the same numbers as the dashboard:

- Funding rows (`isFunding: true`) are never expenses.
- Recurring/subscription templates are expanded into dated occurrences
  (daily/weekly/monthly/yearly, tenure, `skippedOccurrences`).
- total_spent       = outflow dated <= now
- monthly_burn      = this month's occurrences (incl. ones due later this month)
                      + active members' salary not yet paid this month;
                      falls back to the last-3-months average when 0.
- net_burn          = monthly_burn - this month's revenue
- runway_months     = available_funds / net_burn (None when profitable)
"""

from __future__ import annotations

import calendar
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable, Optional

PROFITABLE = "profitable"

_MAX_OCCURRENCES = 2000  # safety cap per template (≈5 years daily)


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def to_float(v: Any) -> float:
    if v is None:
        return 0.0
    if isinstance(v, bool):
        return 0.0
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        cleaned = "".join(ch for ch in v if ch.isdigit() or ch in ".-")
        try:
            return float(cleaned) if cleaned not in ("", "-", ".") else 0.0
        except ValueError:
            return 0.0
    return 0.0


def to_datetime(v: Any) -> Optional[datetime]:
    """Accepts Firestore timestamps (datetime subclasses), datetimes, ISO strings,
    epoch numbers and {_seconds}/{seconds} maps. Returns a naive local-free UTC datetime."""
    if v is None or v == "":
        return None
    dt: Optional[datetime] = None
    if isinstance(v, datetime):
        dt = v
    elif isinstance(v, str):
        try:
            dt = datetime.fromisoformat(v.replace("Z", "+00:00"))
        except ValueError:
            return None
    elif isinstance(v, (int, float)) and not isinstance(v, bool):
        secs = v / 1000 if v > 1e11 else v
        dt = datetime.fromtimestamp(secs, tz=timezone.utc)
    elif isinstance(v, dict):
        secs = v.get("_seconds", v.get("seconds"))
        if isinstance(secs, (int, float)):
            dt = datetime.fromtimestamp(secs, tz=timezone.utc)
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def _add_months(d: datetime, months: int) -> datetime:
    """Dart-style month add, but clamped to the month's last day (no overflow)."""
    total = d.month - 1 + months
    year = d.year + total // 12
    month = total % 12 + 1
    day = min(d.day, calendar.monthrange(year, month)[1])
    return d.replace(year=year, month=month, day=day)


def _same_month(a: datetime, b: datetime) -> bool:
    return a.year == b.year and a.month == b.month


def _month_end(d: datetime) -> datetime:
    last = calendar.monthrange(d.year, d.month)[1]
    return d.replace(day=last, hour=23, minute=59, second=59, microsecond=0)


def _category(e: dict) -> str:
    return str(e.get("Category") or e.get("category") or "others").strip().lower()


def is_salary(e: dict) -> bool:
    return _category(e) in ("salary", "salaries")


def is_salary_payment(e: dict) -> bool:
    """A single salary payment recorded from a member's screen.

    The app stores these with Type='recurring' (legacy) but no
    recurrenceFrequency. Each one is a real, one-off payment; expanding it
    monthly counted the same salary again every month.
    """
    return (
        is_salary(e)
        and not e.get("recurrenceFrequency")
        and (e.get("ExpenseType") == "member" or bool(e.get("memberId")))
    )


def is_recurring(e: dict) -> bool:
    t = str(e.get("Type") or e.get("type") or "one_time").lower()
    return t in ("recurring", "subscription") and not is_salary_payment(e)


# ---------------------------------------------------------------------------
# Timezone: the app stores dates as the user's local time. Firestore returns
# them in UTC, so "1 Oct 00:00 IST" became "30 Sep" and landed in the wrong
# month. Shift every date into the user's local wall-clock time once.
# ---------------------------------------------------------------------------

_DATE_KEYS = ("Date", "date", "joiningDate", "recurringEndDate")
_TZ_KEY = "_tz_offset_minutes"


def localize(data: dict, tz_offset_minutes: int = 0) -> dict:
    """Returns a copy of `data` with date fields as naive local datetimes."""
    shift = timedelta(minutes=tz_offset_minutes or 0)

    def fix(row: dict) -> dict:
        row = dict(row)
        for k in _DATE_KEYS:
            if k in row:
                dt = to_datetime(row[k])
                if dt is not None:
                    row[k] = dt + shift
        return row

    out = dict(data or {})
    for coll in ("expenses", "revenue", "members"):
        out[coll] = [fix(r) for r in (out.get(coll) or []) if isinstance(r, dict)]
    out[_TZ_KEY] = tz_offset_minutes or 0
    return out


def local_now(data: Optional[dict] = None) -> datetime:
    offset = (data or {}).get(_TZ_KEY, 0) or 0
    return datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=offset)


# ---------------------------------------------------------------------------
# Expansion
# ---------------------------------------------------------------------------

def expand_expenses(raw: Iterable[dict], until: datetime) -> list[dict]:
    """Expands recurring templates into occurrences dated <= `until`.

    Funding rows are dropped. Each occurrence carries `_date` (datetime) and
    `_amount` (float). One-time rows with no parseable date keep `_date=None`.
    """
    out: list[dict] = []
    for e in raw:
        if e.get("isFunding") is True:
            continue
        amount = to_float(e.get("Amount", e.get("amount")))
        start = to_datetime(e.get("Date", e.get("date")))

        if not is_recurring(e) or start is None:
            if start is None or start <= until:
                out.append({**e, "_date": start, "_amount": amount})
            continue

        freq = str(e.get("recurrenceFrequency") or "monthly").lower()
        tenure = e.get("recurringTenureMonths", e.get("loanTenureMonths"))
        end = (
            _add_months(start, int(tenure))
            if isinstance(tenure, (int, float)) and not isinstance(tenure, bool)
            else None
        )
        # Explicit stop time (set when a series is stopped) is inclusive.
        stop = to_datetime(e.get("recurringEndDate"))
        if stop is not None:
            stop_excl = stop + timedelta(microseconds=1)
            end = stop_excl if end is None or stop_excl < end else end
        skipped = {
            int(i) for i in (e.get("skippedOccurrences") or [])
            if isinstance(i, (int, float))
        }

        i = 0
        while i < _MAX_OCCURRENCES:
            if freq == "daily":
                occ = start + _days(i)
            elif freq == "weekly":
                occ = start + _days(7 * i)
            elif freq == "yearly":
                occ = _add_months(start, 12 * i)
            else:
                occ = _add_months(start, i)
            if occ > until or (end is not None and occ >= end):
                break
            if i not in skipped:
                out.append({**e, "_date": occ, "_amount": amount, "_occurrence": i})
            i += 1
    return out


def _days(n: int) -> timedelta:
    return timedelta(days=n)


# ---------------------------------------------------------------------------
# Snapshot
# ---------------------------------------------------------------------------

def compute_snapshot(data: dict, now: Optional[datetime] = None) -> dict:
    """Returns verified metrics + compact derived lists for the prompt."""
    now = now or local_now(data)
    month_end = _month_end(now)

    company = data.get("company") or {}
    members = data.get("members") or []
    revenue = data.get("revenue") or []
    teams = data.get("teams") or []
    raw_expenses = data.get("expenses") or []

    funding = to_float(company.get("Funding", company.get("funding")))
    occurrences = expand_expenses(raw_expenses, until=month_end)

    total_spent = 0.0
    current_month_expenses = 0.0
    monthly: dict[str, float] = {}
    monthly_by_category: dict[str, dict[str, float]] = {}
    categories_all: dict[str, float] = {}
    categories_month: dict[str, float] = {}
    paid_members: set[str] = set()

    for o in occurrences:
        d, amt, cat = o["_date"], o["_amount"], _category(o)
        if d is None:
            continue
        if d <= now:
            total_spent += amt
            key = d.strftime("%Y-%m")
            monthly[key] = monthly.get(key, 0.0) + amt
            categories_all[cat] = categories_all.get(cat, 0.0) + amt
            per_cat = monthly_by_category.setdefault(key, {})
            per_cat[cat] = per_cat.get(cat, 0.0) + amt
        if _same_month(d, now):
            current_month_expenses += amt
            categories_month[cat] = categories_month.get(cat, 0.0) + amt
            mid = o.get("memberId") or o.get("TeamMemberId")
            if mid and is_salary(o):
                paid_members.add(str(mid))

    active_members = [
        m for m in members if str(m.get("status") or "Active") == "Active"
    ]
    payroll_monthly = sum(
        to_float(m.get("monthlyCost", m.get("salary"))) for m in active_members
    )
    unpaid_payroll = 0.0
    for m in active_members:
        mid = m.get("id") or m.get("_id")
        if mid and str(mid) in paid_members:
            continue
        joining = to_datetime(m.get("joiningDate"))
        if joining and joining > month_end:
            continue
        unpaid_payroll += to_float(m.get("monthlyCost", m.get("salary")))
    if unpaid_payroll:
        categories_month["salary"] = categories_month.get("salary", 0.0) + unpaid_payroll

    monthly_burn = current_month_expenses + unpaid_payroll
    burn_estimated = False
    if monthly_burn <= 0 and monthly:
        recent = sorted(monthly.keys(), reverse=True)[:3]
        monthly_burn = sum(monthly[k] for k in recent) / len(recent)
        burn_estimated = True

    monthly_revenue = 0.0
    total_revenue = 0.0
    for r in revenue:
        d = to_datetime(r.get("Date", r.get("date")))
        amt = to_float(r.get("Amount", r.get("amount")))
        if d and d <= now:
            total_revenue += amt
        if d and _same_month(d, now):
            monthly_revenue += amt

    net_burn = monthly_burn - monthly_revenue
    available = funding - total_spent

    if available <= 0 or monthly_burn <= 0:
        runway: Any = 0.0
    elif net_burn <= 0:
        runway = PROFITABLE
    else:
        runway = available / net_burn

    # Recurring subscriptions = recurring templates that are not salary/EMI.
    subscriptions = []
    for e in raw_expenses:
        if e.get("isFunding") is True or not is_recurring(e) or is_salary(e):
            continue
        if e.get("isEmiRepayment"):
            continue
        subscriptions.append({
            "title": e.get("Title") or e.get("Description") or "Untitled",
            "amount": to_float(e.get("Amount")),
            "frequency": str(e.get("recurrenceFrequency") or "monthly"),
            "category": _category(e),
        })

    # Funding rounds and loan EMIs, so "list my funding rounds" / "what are my
    # EMIs" can be answered from data instead of guessed.
    funding_rounds = []
    emis = []
    for e in raw_expenses:
        if e.get("isFunding") is True:
            fd = to_datetime(e.get("Date", e.get("date")))
            funding_rounds.append({
                "title": e.get("fundingSource") or e.get("Title") or "Funding",
                "amount": to_float(e.get("Amount")),
                "date": fd.strftime("%d %b %Y") if fd else "",
                "_sort": fd or datetime.min,
            })
        elif e.get("isEmiRepayment"):
            paid = sum(
                1 for o in occurrences
                if o.get("id") == e.get("id") and o["_date"] is not None and o["_date"] <= now
            ) if e.get("id") else None
            emis.append({
                "title": e.get("Title") or "Loan EMI",
                "amount": to_float(e.get("Amount")),
                "tenure": e.get("recurringTenureMonths", e.get("loanTenureMonths")),
                "paid": paid,
            })
    funding_rounds.sort(key=lambda r: r.pop("_sort"), reverse=True)

    dated = [o for o in occurrences if o["_date"] is not None and o["_date"] <= now]
    recent_expenses = sorted(dated, key=lambda o: o["_date"], reverse=True)[:15]
    largest_expenses = sorted(dated, key=lambda o: o["_amount"], reverse=True)[:5]

    team_names = {t.get("id"): t.get("teamName") for t in teams if t.get("id")}
    team_spend_month: dict[str, float] = {}
    for o in occurrences:
        d = o["_date"]
        if d is None or not _same_month(d, now):
            continue
        name = o.get("TeamName") or team_names.get(o.get("TeamId"))
        if name:
            team_spend_month[name] = team_spend_month.get(name, 0.0) + o["_amount"]

    return {
        "as_of": now.strftime("%Y-%m-%d"),
        "current_month": now.strftime("%B %Y"),
        "funding_total": funding,
        "total_spent": total_spent,
        "available_funds": available,
        "monthly_burn": monthly_burn,
        "burn_is_estimate": burn_estimated,
        "current_month_expenses": current_month_expenses,
        # Already paid this month (dated <= now). current_month_expenses also
        # includes recurring charges still due later this month.
        "current_month_spent_to_date": monthly.get(now.strftime("%Y-%m"), 0.0),
        "monthly_by_category": {
            k: dict(sorted(v.items(), key=lambda x: -x[1]))
            for k, v in sorted(monthly_by_category.items())
        },
        "funding_rounds": funding_rounds,
        "emis": emis,
        "unpaid_payroll_this_month": unpaid_payroll,
        "monthly_revenue": monthly_revenue,
        "total_revenue": total_revenue,
        "net_burn": net_burn,
        "runway_months": runway,
        "payroll_monthly": payroll_monthly,
        "active_members": len(active_members),
        "total_members": len(members),
        "team_count": len(teams),
        "team_names": [t.get("teamName") or "Unnamed" for t in teams],
        "categories_this_month": dict(sorted(categories_month.items(), key=lambda x: -x[1])),
        "categories_all_time": dict(sorted(categories_all.items(), key=lambda x: -x[1])),
        "monthly_totals": dict(sorted(monthly.items())),
        "team_spend_this_month": team_spend_month,
        "subscriptions": subscriptions,
        "recent_expenses": [_compact(o) for o in recent_expenses],
        "largest_expenses": [_compact(o) for o in largest_expenses],
        "has_data": bool(raw_expenses or members or revenue),
    }


def _compact(o: dict) -> dict:
    return {
        "title": o.get("Title") or o.get("Description") or "Untitled",
        "amount": o["_amount"],
        "category": _category(o),
        "date": o["_date"].strftime("%d %b %Y") if o["_date"] else "",
        "recurring": is_recurring(o),
    }


def risk_level(snapshot: dict) -> str:
    """Currency-independent risk based on runway, not absolute amounts."""
    r = snapshot["runway_months"]
    if r == PROFITABLE:
        return "Low"
    if not snapshot["has_data"] or snapshot["monthly_burn"] <= 0:
        return "Unknown"
    if r <= 3:
        return "High"
    if r <= 6:
        return "Medium"
    return "Low"


def fmt_money(v: float, cs: str) -> str:
    sign = "-" if v < 0 else ""
    return f"{sign}{cs}{abs(v):,.2f}"


def fmt_runway(r: Any) -> str:
    if r == PROFITABLE:
        return "Profitable (revenue covers burn)"
    if not r:
        return "0 months (no cash left or no burn data)"
    if r > 120:
        return "10+ years"
    return f"{r:.1f} months"
