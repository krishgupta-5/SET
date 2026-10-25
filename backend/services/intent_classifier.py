import re

def classify_intent(question: str) -> str:
    """
    Lightweight rule-based intent classifier.
    Returns the classified intent based on keywords.
    """
    q = question.lower()

    # Topic keywords are checked first. Date words ("monthly", "this month")
    # only matter when no topic matched — previously they ran first and sent
    # "what's my monthly burn?" to Expense Optimization.
    if re.search(r'\b(burn|burn rate|spending speed|spending rate|losing money|spend rate|burning)\b', q):
        return 'Burn Rate'
    elif re.search(r'\b(runway|months left|survival|how long|survive|run out of money)\b', q):
        return 'Runway'
    elif re.search(r'\b(reduce|cut|optimize|save|expensive|too much|cheaper|lower|decrease|trim)\b', q):
        return 'Expense Optimization'
    # Payroll BEFORE Team so "team salaries" matches salary first
    elif re.search(r'\b(payroll|salar\w+|compensation|wages|paying|benefits|bonus)\b', q):
        return 'Payroll'
    elif re.search(r'\b(hire|hiring|recruit|headcount|new employee|bring on)\b', q):
        return 'Hiring'
    elif re.search(r'\b(teams?|employees?|members?|staff|personnel|workforce|how many people)\b', q):
        return 'Team'
    elif re.search(r'\b(marketing|ads|campaign|facebook|google ads|seo|promotion|advertising|acquisition)\b', q):
        return 'Marketing'
    elif re.search(r'\b(aws|cloud|server|infrastructure|hosting|database|compute|gcp|azure)\b', q):
        return 'Infrastructure'
    elif re.search(r'\b(subscriptions?|saas|recurring|software|tool|app|license|monthly fee|github|slack|notion)\b', q):
        return 'Subscriptions'
    elif re.search(r'\b(revenue|sales|income|mrr|arr|earning|make money|profit|top line|selling)\b', q):
        return 'Revenue'
    elif re.search(r'\b(cash|cash flow|balance|funding|money left|bank account|capital|funds|left)\b', q):
        return 'Cash Flow'
    elif re.search(r'\b(invest|investor|raise|round|vc|seed|angel|pitch|valuation)\b', q):
        return 'Investment'
    elif re.search(r'\b(health|status|summary|overview|doing|performance|metrics|startup doing|how are we|how am i)\b', q):
        return 'Financial Health'
    # Company info queries
    elif re.search(r'\b(company name|company info|about my company|founded|founder|who am i|my startup|my company)\b', q):
        return 'Financial Health'
    elif re.search(r'\b(transactions?|all expenses|all spending|expense list|expense history)\b', q):
        return 'Expense Optimization'
    elif re.search(r'\b(forecast|predict|projection|next quarter|next month|future)\b', q):
        return 'Financial Health'
    elif re.search(r'\b(expenses?|spending|spent|costs?|bills?|payments?)\b', q):
        return 'Expense Optimization'
    elif re.search(r'\b(january|february|march|april|may|june|july|august|september|october|november|december|this month|last month|monthly|month wise|month-wise|week|weekly|today|yesterday|this year|last year)\b', q):
        return 'Expense Optimization'
    elif re.search(r'\b(advice|tips?|strategy|grow|growth|recommendation|should i|what if|plan)\b', q):
        return 'General Startup Advice'
    
    return 'Unknown'
