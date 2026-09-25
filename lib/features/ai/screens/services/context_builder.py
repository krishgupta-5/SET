import pandas as pd

def build_business_summary(data: dict, currency_symbol: str = "$") -> str:
    company = data.get('company', {})
    expenses = data.get('expenses', [])
    revenue = data.get('revenue', [])
    members = data.get('members', [])
    teams = data.get('teams', [])
    
    # Company fields (matching actual Firestore schema)
    company_name = company.get('Company Name', company.get('name', 'Unknown Startup'))
    company_type = company.get('Company Type', company.get('stage', 'Unknown'))
    company_work = company.get('Company Work', '')
    country = company.get('Country Location', 'Unknown')
    runway_months = company.get('Runway', 'Unknown')
    funding = float(company.get('Funding', 0) or 0)
    total_expenses_recorded = float(company.get('totalExpenses', 0) or 0)
    
    # Use explicitly provided currency symbol
    currency = currency_symbol
    
    # Calculate Expenses from raw data
    total_expenses = 0
    expense_categories = {}
    top_expenses = []
    subscriptions = []
    
    if expenses:
        expense_df = pd.DataFrame(expenses)
        if 'Amount' in expense_df.columns:
            expense_df['Amount'] = pd.to_numeric(expense_df['Amount'], errors='coerce').fillna(0)
            total_expenses = float(expense_df['Amount'].sum())
            
            if 'Category' in expense_df.columns:
                expense_categories = expense_df.groupby('Category')['Amount'].sum().to_dict()
                
            sorted_exp = expense_df.sort_values(by='Amount', ascending=False)
            top_expenses = sorted_exp.head(5).to_dict('records')
            
            if 'Type' in expense_df.columns:
                subscriptions = expense_df[expense_df['Type'].str.lower() == 'recurring'].to_dict('records')

    # Use the larger of calculated vs recorded total
    if total_expenses_recorded > total_expenses:
        total_expenses = total_expenses_recorded

    # Calculate Revenue
    total_revenue = 0
    if revenue:
        rev_df = pd.DataFrame(revenue)
        if 'Amount' in rev_df.columns:
            rev_df['Amount'] = pd.to_numeric(rev_df['Amount'], errors='coerce').fillna(0)
            total_revenue = float(rev_df['Amount'].sum())
            
    net_burn = total_expenses - total_revenue
    funding_remaining = funding - total_expenses
    if funding_remaining < 0:
        funding_remaining = 0
    
    # Calculate Payroll
    payroll = sum([float(m.get('salary', m.get('monthlyCost', 0)) or 0) for m in members])
    
    # Team info
    team_names = [t.get('teamName', 'Unknown') for t in teams]
    
    summary = f"""=== VERIFIED BUSINESS DATA (use ONLY these numbers) ===
Company: {company_name}
Type: {company_type}
Industry: {company_work}
Country: {country}
Currency: {currency}

FINANCIAL DATA (all amounts in {currency}):
- Initial Funding: {currency}{funding:,.2f}
- Total Expenses (all time): {currency}{total_expenses:,.2f}
- Total Revenue (all time): {currency}{total_revenue:,.2f}
- Net Burn (all time): {currency}{net_burn:,.2f}
- Funding Remaining: {currency}{funding_remaining:,.2f}
- Runway: {runway_months} months
- Payroll: {currency}{payroll:,.2f}/month
- Employees: {len(members)}
- Teams ({len(teams)}): {', '.join(team_names) if team_names else 'None'}

IMPORTANT: All monetary values are in {currency} (NOT USD). Do NOT convert or assume USD.

Expense Breakdown by Category:
"""
    for cat, amt in sorted(expense_categories.items(), key=lambda x: x[1], reverse=True)[:5]:
        summary += f"- {cat}: {currency}{amt:,.2f}\n"
    
    if not expense_categories:
        summary += "- No expense categories recorded yet.\n"
        
    summary += "\nRecurring Subscriptions:\n"
    if subscriptions:
        for sub in subscriptions:
            summary += f"- {sub.get('Title', sub.get('Description', 'Unknown'))}: {currency}{sub.get('Amount', 0):,.2f}\n"
    else:
        summary += "- No recurring subscriptions found.\n"
        
    summary += "\nTop Recent Expenses:\n"
    if top_expenses:
        for exp in top_expenses:
            summary += f"- {exp.get('Title', exp.get('Description', 'Unknown'))}: {currency}{exp.get('Amount', 0):,.2f}\n"
    else:
        summary += "- No expenses recorded yet.\n"
        
    return summary

