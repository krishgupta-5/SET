import re

def classify_intent(question: str) -> str:
    """
    Lightweight rule-based intent classifier.
    Returns the classified intent based on keywords.
    """
    q = question.lower()
    
    if re.search(r'\b(burn|burn rate|spending speed|spending rate|losing money|spend rate|burning)\b', q):
        return 'Burn Rate'
    elif re.search(r'\b(runway|months left|survival|how long|survive|run out of money)\b', q):
        return 'Runway'
    elif re.search(r'\b(reduce|cut|optimize|save|expensive|too much|cheaper|lower|decrease|trim)\b', q):
        return 'Expense Optimization'
    elif re.search(r'\b(payroll|salary|pay|compensation|wages|paying|benefits|bonus)\b', q):
        return 'Payroll'
    elif re.search(r'\b(hire|hiring|recruit|headcount|new employee|bring on|developer|engineer|designer)\b', q):
        return 'Hiring'
    elif re.search(r'\b(team|employee|member|staff|personnel|workforce)\b', q):
        return 'Team'
    elif re.search(r'\b(marketing|ads|campaign|facebook|google ads|seo|promotion|advertising|growth|acquisition)\b', q):
        return 'Marketing'
    elif re.search(r'\b(aws|cloud|server|infrastructure|hosting|database|compute|gcp|azure)\b', q):
        return 'Infrastructure'
    elif re.search(r'\b(subscription|saas|recurring|software|tool|app|license|monthly fee|github|slack|notion)\b', q):
        return 'Subscriptions'
    elif re.search(r'\b(revenue|sales|income|mrr|arr|earning|make money|profit|top line|selling)\b', q):
        return 'Revenue'
    elif re.search(r'\b(cash|cash flow|balance|funding|money left|bank account|capital|funds)\b', q):
        return 'Cash Flow'
    elif re.search(r'\b(invest|investor|raise|round|vc|seed|angel|pitch|valuation)\b', q):
        return 'Investment'
    elif re.search(r'\b(health|status|summary|overview|doing well|performance|metrics)\b', q):
        return 'Financial Health'
    elif re.search(r'\b(advice|tip|strategy|grow|recommendation|should i|what if|plan)\b', q):
        return 'General Startup Advice'
    
    return 'Unknown'
