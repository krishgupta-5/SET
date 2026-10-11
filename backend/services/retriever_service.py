def determine_required_collections(intent: str) -> list:
    """
    Determines which Firestore collections are needed based on the intent.
    'base' includes company and basic summary data.
    """
    if intent == 'Expense Optimization':
        return ['base', 'expenses']
    elif intent in ['Burn Rate', 'Runway', 'Cash Flow', 'Financial Health']:
        return ['base', 'expenses', 'revenue']
    elif intent in ['Payroll', 'Hiring', 'Team']:
        return ['base', 'members', 'teams']
    elif intent == 'Marketing':
        return ['base', 'expenses']
    elif intent == 'Infrastructure':
        return ['base', 'expenses']
    elif intent == 'Subscriptions':
        return ['base', 'expenses']
    elif intent == 'Revenue':
        return ['base', 'revenue']
    elif intent == 'Investment':
        return ['base', 'revenue', 'expenses']
    else:
        # Default to base for general advice or unknown
        return ['base']

def retrieve_relevant_data(intent: str, summary: str, full_data: dict, currency_symbol: str = "$") -> str:
    """
    Builds a retrieved context string containing only the necessary granular data.
    The 'summary' string already contains high-level metrics.
    """
    retrieved = f"Identified Topic: {intent}\n\n"
    
    if intent in ['Payroll', 'Hiring', 'Team']:
        retrieved += "Granular Team Data:\n"
        members = full_data.get('members', [])
        if members:
            for m in members:
                retrieved += f"- {m.get('fullName', 'Unknown')} ({m.get('jobTitle', m.get('role', 'Unknown'))}): {currency_symbol}{m.get('monthlyCost', m.get('salary', 0))}/mo | {m.get('employmentType', 'N/A')} | {m.get('status', 'N/A')}\n"
        else:
            retrieved += "No team members found.\n"
            
    elif intent in ['Expense Optimization', 'Subscriptions']:
        retrieved += "All Expenses (with dates):\n"
        expenses = full_data.get('expenses', [])
        if expenses:
            for e in expenses[:30]:  # Limit to avoid token overflow
                date_str = _fmt_date(e.get('Date', ''))
                date_part = f" [{date_str}]" if date_str else ""
                exp_type = e.get('Type', '')
                type_tag = " [Recurring]" if exp_type.lower() == 'recurring' else ""
                cat = e.get('Category', '')
                cat_part = f" ({cat})" if cat else ""
                retrieved += f"- {e.get('Title', e.get('Description', 'Unknown'))}: {currency_symbol}{e.get('Amount', 0)}{cat_part}{date_part}{type_tag}\n"
        else:
            retrieved += "No expenses recorded.\n"
                
    elif intent == 'Marketing':
        retrieved += "Marketing Expenses:\n"
        for e in full_data.get('expenses', []):
            if e.get('Category', '').lower() == 'marketing':
                date_str = _fmt_date(e.get('Date', ''))
                date_part = f" [{date_str}]" if date_str else ""
                retrieved += f"- {e.get('Title', e.get('Description', 'Unknown'))} ({currency_symbol}{e.get('Amount', 0)}){date_part}\n"

    elif intent in ['Burn Rate', 'Runway', 'Cash Flow', 'Financial Health']:
        retrieved += "All Expenses (with dates):\n"
        expenses = full_data.get('expenses', [])
        if expenses:
            for e in expenses[:30]:  # Limit to avoid token overflow
                date_str = _fmt_date(e.get('Date', ''))
                date_part = f" [{date_str}]" if date_str else ""
                cat = e.get('Category', '')
                cat_part = f" ({cat})" if cat else ""
                retrieved += f"- {e.get('Title', e.get('Description', 'Unknown'))}: {currency_symbol}{e.get('Amount', 0)}{cat_part}{date_part}\n"
        else:
            retrieved += "No expenses recorded.\n"

    return retrieved


def _fmt_date(date_val) -> str:
    """Safely format a date value for retriever output."""
    if not date_val:
        return ''
    if isinstance(date_val, str):
        try:
            from datetime import datetime
            dt = datetime.fromisoformat(date_val.replace('Z', '+00:00'))
            return dt.strftime('%d %b %Y')
        except (ValueError, TypeError):
            return date_val
    if hasattr(date_val, 'strftime'):
        return date_val.strftime('%d %b %Y')
    return str(date_val)

