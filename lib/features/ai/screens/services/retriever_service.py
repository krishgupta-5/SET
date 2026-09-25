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
                retrieved += f"- {m.get('fullName', 'Unknown')} ({m.get('role', 'Unknown')}): {currency_symbol}{m.get('salary', 0)}/yr\n"
        else:
            retrieved += "No team members found.\n"
            
    elif intent in ['Expense Optimization', 'Subscriptions']:
        retrieved += "Recent/Recurring Expenses Details:\n"
        expenses = full_data.get('expenses', [])
        for e in expenses:
            # Add some granular details not in summary if needed
            # E.g. recurring explicitly
            if e.get('Type', '').lower() == 'recurring':
                retrieved += f"- Recurring: {e.get('Title', 'Unknown')} ({currency_symbol}{e.get('Amount', 0)})\n"
                
    elif intent == 'Marketing':
        retrieved += "Marketing Expenses:\n"
        for e in full_data.get('expenses', []):
            if e.get('Category', '').lower() == 'marketing':
                retrieved += f"- {e.get('Title', 'Unknown')} ({currency_symbol}{e.get('Amount', 0)})\n"
                
    return retrieved
