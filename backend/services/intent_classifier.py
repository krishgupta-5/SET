import re

# Ordered (intent, pattern) rules; the first match wins.
# Topic keywords come before date words ("monthly", "this month") so
# "what's my monthly burn?" is Burn Rate, not Expense Optimization.
# Common typos and Hinglish terms are included because users type them.
_RULES = [
    ('Burn Rate', r'\b(burn|burn ?rate|brun|bunr|spending speed|spending rate|losing money|spend rate|burning)\b'),
    ('Runway', r'\b(runway|run way|runaway|runwy|months left|survival|how long|survive|run out of money|kab tak|kitne mahine)\b'),
    ('Expense Optimization', r'\b(reduce|cut|optimi[sz]e|save|saving|expensive|too much|cheaper|lower|decrease|trim|bachat|kam kar\w*)\b'),
    # Payroll BEFORE Team so "team salaries" matches salary first
    ('Payroll', r'\b(payroll|salar\w*|sallary|compensation|wages|paying|benefits|bonus|tankh?(wa|ah?|wah)\w*|pagaar)\b'),
    ('Hiring', r'\b(hire|hiring|recruit\w*|headcount|new employee|bring on|bharti)\b'),
    ('Team', r'\b(teams?|employees?|members?|staff|personnel|workforce|how many people)\b'),
    ('Marketing', r'\b(marketing|ads|campaigns?|facebook|google ads|seo|promotion|advertising|acquisition)\b'),
    ('Infrastructure', r'\b(aws|cloud|servers?|infrastructure|hosting|database|compute|gcp|azure)\b'),
    # "app" alone is not a subscription signal: "how is my app doing" is health.
    ('Subscriptions', r'\b(subscriptions?|subs|saas|recurring|software|tools?|licen[cs]e|monthly fee|github|slack|notion|figma)\b'),
    ('Revenue', r'\b(revenue|sales|income|mrr|arr|earning|make money|profit|loss|top line|selling|kamai)\b'),
    ('Cash Flow', r'\b(emis?|loans?|repayment|debt|interest|lender)\b'),
    ('Investment', r'\b(invest\w*|raised?|round|rounds|vc|seed|angel|pitch|valuation|funding rounds?)\b'),
    ('Cash Flow', r'\b(cash|cash flow|balance|funding|funds?|money left|bank account|capital|left|paisa|paise|bacha|bache)\b'),
    ('Financial Health', r'\b(health|status|summary|overview|doing|performance|metrics|startup doing|how are we|how am i|business|kaisa|kaise)\b'),
    ('Financial Health', r'\b(company name|company info|about my company|founded|founder|who am i|my startup|my company)\b'),
    ('Expense Optimization', r'\b(transactions?|all expenses|all spending|expense list|expense history|where.*money (go|going|went))\b'),
    ('Financial Health', r'\b(forecast|predict|projection|next quarter|next month|future)\b'),
    ('Expense Optimization', r'\b(expenses?|expence\w*|spending|spent|spend|costs?|bills?|payments?|kharch\w*|kharcha)\b'),
    ('Expense Optimization', r'\b(january|february|march|april|may|june|july|august|september|october|november|december|this month|last month|monthly|month wise|month-wise|week|weekly|today|yesterday|this year|last year|mahine|mahina)\b'),
    ('General Startup Advice', r'\b(advice|tips?|strategy|grow|growth|recommendation|should i|what if|plan|tax|gst)\b'),
]
_COMPILED = [(intent, re.compile(p)) for intent, p in _RULES]


def classify_intent(question: str) -> str:
    """Lightweight rule-based intent classifier. Returns 'Unknown' when no
    rule matches; the retriever still sends full expense history then."""
    q = (question or "").lower()
    for intent, pattern in _COMPILED:
        if pattern.search(q):
            return intent
    return 'Unknown'
