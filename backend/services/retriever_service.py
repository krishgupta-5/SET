"""Adds intent-specific detail on top of the business summary."""

from .context_builder import clean_text
from .metrics_service import expand_expenses, fmt_money, to_datetime, _month_end, _category
from datetime import datetime, timezone

_MAX_ROWS = 40


def determine_required_collections(intent: str) -> list:
    """Kept for compatibility; the backend now loads all collections because
    every metric (burn, runway) depends on expenses, members and revenue."""
    return ['base', 'expenses', 'revenue', 'members', 'teams']


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _expense_rows(full_data: dict, currency_symbol: str, category: str = None) -> list:
    now = _now()
    occ = [
        o for o in expand_expenses(full_data.get('expenses') or [], until=now)
        if o["_date"] is not None and (category is None or _category(o) == category)
    ]
    occ.sort(key=lambda o: o["_date"], reverse=True)
    rows = []
    for o in occ[:_MAX_ROWS]:
        tag = " [recurring]" if str(o.get('Type', '')).lower() in ('recurring', 'subscription') else ""
        rows.append(
            f"- {clean_text(o.get('Title') or o.get('Description') or 'Untitled')}: "
            f"{fmt_money(o['_amount'], currency_symbol)} ({_category(o)}) "
            f"[{o['_date'].strftime('%d %b %Y')}]{tag}"
        )
    if len(occ) > _MAX_ROWS:
        rows.append(f"- …and {len(occ) - _MAX_ROWS} older entries (totals above already include them).")
    return rows or ["- No expenses recorded."]


def retrieve_relevant_data(intent: str, summary: str, full_data: dict, currency_symbol: str = "$") -> str:
    retrieved = f"Identified Topic: {intent}\n\n"

    if intent in ['Payroll', 'Hiring', 'Team']:
        retrieved += "Team Members:\n"
        members = full_data.get('members') or []
        teams = {t.get('id'): t.get('teamName') for t in (full_data.get('teams') or [])}
        if members:
            for m in members:
                cost = fmt_money(float(m.get('monthlyCost') or m.get('salary') or 0), currency_symbol)
                team = teams.get(m.get('teamId')) or 'No team'
                retrieved += (
                    f"- {clean_text(m.get('fullName') or 'Unknown')} "
                    f"({clean_text(m.get('jobTitle') or m.get('role') or 'Unknown role')}, {clean_text(team, 30)}): "
                    f"{cost}/mo | {clean_text(m.get('employmentType') or 'N/A', 20)} | {m.get('status') or 'Active'}\n"
                )
        else:
            retrieved += "- No team members found.\n"
        if intent == 'Hiring':
            retrieved += "\nRecent spending (for affordability):\n" + "\n".join(_expense_rows(full_data, currency_symbol)[:15]) + "\n"

    elif intent in ['Expense Optimization', 'Subscriptions', 'Burn Rate', 'Runway', 'Cash Flow', 'Financial Health', 'Investment']:
        retrieved += "Expense history (newest first, recurring charges expanded, funding excluded):\n"
        retrieved += "\n".join(_expense_rows(full_data, currency_symbol)) + "\n"

    elif intent == 'Marketing':
        retrieved += "Marketing expenses:\n" + "\n".join(_expense_rows(full_data, currency_symbol, 'marketing')) + "\n"

    elif intent == 'Infrastructure':
        retrieved += "Infrastructure expenses:\n" + "\n".join(_expense_rows(full_data, currency_symbol, 'infrastructure')) + "\n"
        retrieved += "\nSoftware expenses:\n" + "\n".join(_expense_rows(full_data, currency_symbol, 'software')) + "\n"

    elif intent == 'Revenue':
        retrieved += "Revenue entries:\n"
        revenue = full_data.get('revenue') or []
        if revenue:
            for r in revenue[:_MAX_ROWS]:
                d = to_datetime(r.get('Date'))
                retrieved += (
                    f"- {clean_text(r.get('Title') or r.get('Source') or 'Revenue')}: "
                    f"{fmt_money(float(r.get('Amount') or 0), currency_symbol)}"
                    f"{' [' + d.strftime('%d %b %Y') + ']' if d else ''}\n"
                )
        else:
            retrieved += "- No revenue recorded in the app.\n"

    return retrieved
