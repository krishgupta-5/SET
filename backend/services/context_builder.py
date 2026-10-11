import pandas as pd
from datetime import datetime

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
    runway_raw = company.get('Runway', 'Unknown')
    # Strip trailing "months" if present to avoid "12.20 months months"
    runway_months = str(runway_raw).replace(' months', '').strip() if runway_raw else 'Unknown'
    funding = float(company.get('Funding', 0) or 0)
    total_expenses_recorded = float(company.get('totalExpenses', 0) or 0)
    
    # Use explicitly provided currency symbol
    currency = currency_symbol
    
    # Calculate Expenses from raw data
    total_expenses = 0
    expense_categories = {}
    top_expenses = []
    subscriptions = []
    month_wise = {}
    
    if expenses:
        expense_df = pd.DataFrame(expenses)
        if 'Amount' in expense_df.columns:
            expense_df['Amount'] = pd.to_numeric(expense_df['Amount'], errors='coerce').fillna(0)
            total_expenses = float(expense_df['Amount'].sum())
            
            if 'Category' in expense_df.columns:
                expense_categories = expense_df.groupby('Category')['Amount'].sum().to_dict()
            
            # Parse dates for month-wise breakdown
            month_wise = {}
            if 'Date' in expense_df.columns:
                for _, row in expense_df.iterrows():
                    date_val = row.get('Date', '')
                    month_key = None
                    if isinstance(date_val, str) and date_val:
                        try:
                            dt = datetime.fromisoformat(date_val.replace('Z', '+00:00'))
                            month_key = dt.strftime('%Y-%m')
                        except (ValueError, TypeError):
                            pass
                    elif hasattr(date_val, 'strftime'):
                        month_key = date_val.strftime('%Y-%m')
                    if month_key:
                        month_wise[month_key] = month_wise.get(month_key, 0) + float(row.get('Amount', 0))

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
    payroll = sum([float(m.get('monthlyCost', m.get('salary', 0)) or 0) for m in members])
    
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

    # Month-wise spending breakdown
    summary += "\nMonth-wise Spending:\n"
    if month_wise:
        for month_key in sorted(month_wise.keys(), reverse=True):
            try:
                label = datetime.strptime(month_key, '%Y-%m').strftime('%B %Y')
            except ValueError:
                label = month_key
            summary += f"- {label}: {currency}{month_wise[month_key]:,.2f}\n"
    else:
        summary += "- No dated expense data available.\n"
        
    summary += "\nRecurring Subscriptions:\n"
    if subscriptions:
        for sub in subscriptions:
            date_str = _format_date(sub.get('Date', ''))
            date_suffix = f" (on {date_str})" if date_str else ""
            summary += f"- {sub.get('Title', sub.get('Description', 'Unknown'))}: {currency}{sub.get('Amount', 0):,.2f}{date_suffix}\n"
    else:
        summary += "- No recurring subscriptions found.\n"
        
    summary += "\nTop Recent Expenses:\n"
    if top_expenses:
        for exp in top_expenses:
            date_str = _format_date(exp.get('Date', ''))
            date_suffix = f" ({date_str})" if date_str else ""
            summary += f"- {exp.get('Title', exp.get('Description', 'Unknown'))}: {currency}{exp.get('Amount', 0):,.2f}{date_suffix}\n"
    else:
        summary += "- No expenses recorded yet.\n"
        
    return summary


def _format_date(date_val) -> str:
    """Safely format a date value to a readable string."""
    if not date_val:
        return ''
    if isinstance(date_val, str):
        try:
            dt = datetime.fromisoformat(date_val.replace('Z', '+00:00'))
            return dt.strftime('%d %b %Y')
        except (ValueError, TypeError):
            return date_val
    if hasattr(date_val, 'strftime'):
        return date_val.strftime('%d %b %Y')
    return str(date_val)
