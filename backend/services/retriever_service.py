"""Adds intent-specific detail on top of the business summary."""

from .context_builder import clean_text
from datetime import datetime

from .metrics_service import expand_expenses, fmt_money, to_datetime, to_float, local_now, _category, is_recurring

_MAX_ROWS = 40


def determine_required_collections(intent: str) -> list:
    """Kept for compatibility; the backend now loads all collections because
    every metric (burn, runway) depends on expenses, members and revenue."""
    return ['base', 'expenses', 'revenue', 'members', 'teams']


def _expense_rows(full_data: dict, currency_symbol: str, category=None) -> list:
    """`category` may be a single lowercase category or a tuple of them."""
    now = local_now(full_data)
    cats = (category,) if isinstance(category, str) else category
    occ = [
        o for o in expand_expenses(full_data.get('expenses') or [], until=now)
        if o["_date"] is not None and (cats is None or _category(o) in cats)
    ]
    occ.sort(key=lambda o: o["_date"], reverse=True)
    rows = []
    for o in occ[:_MAX_ROWS]:
        tag = " [recurring]" if is_recurring(o) else ""
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
                cost = fmt_money(to_float(m.get('monthlyCost', m.get('salary'))), currency_symbol)
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
        else:
            # "How much salary did I pay in September?" needs the payments,
            # not just the member list.
            retrieved += "\nSalary payments recorded (newest first):\n"
            retrieved += "\n".join(_expense_rows(full_data, currency_symbol, ('salary', 'salaries'))) + "\n"

    elif intent == 'Marketing':
        retrieved += "Marketing expenses:\n" + "\n".join(_expense_rows(full_data, currency_symbol, 'marketing')) + "\n"

    elif intent == 'Infrastructure':
        retrieved += "Infrastructure expenses:\n" + "\n".join(_expense_rows(full_data, currency_symbol, 'infrastructure')) + "\n"
        retrieved += "\nSoftware expenses:\n" + "\n".join(_expense_rows(full_data, currency_symbol, 'software')) + "\n"

    elif intent == 'Revenue':
        retrieved += "Revenue entries:\n"
        revenue = full_data.get('revenue') or []
        if revenue:
            revenue = sorted(revenue, key=lambda r: to_datetime(r.get('Date')) or datetime.min, reverse=True)
            for r in revenue[:_MAX_ROWS]:
                d = to_datetime(r.get('Date'))
                retrieved += (
                    f"- {clean_text(r.get('Title') or r.get('Source') or 'Revenue')}: "
                    f"{fmt_money(to_float(r.get('Amount')), currency_symbol)}"
                    f"{' [' + d.strftime('%d %b %Y') + ']' if d else ''}\n"
                )
        else:
            retrieved += "- No revenue recorded in the app.\n"

    else:
        # Every other topic, including 'Unknown' (typos, Hinglish, small
        # talk), still gets the transaction list so the bot is never blind.
        retrieved += "Expense history (newest first, recurring charges expanded, funding excluded):\n"
        retrieved += "\n".join(_expense_rows(full_data, currency_symbol)) + "\n"

    return retrieved
