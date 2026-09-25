from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import requests
import os
import pandas as pd
import json
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="AI CFO Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

API_KEY = os.getenv("GROQ_API_KEY")


# ---------------------------
# GROQ CALL
# ---------------------------
def call_llm(prompt):
    try:
        response = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json"
            },
            json={
                "model": "openai/gpt-oss-20b",
                "messages": [
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                "response_format": {"type": "json_object"},
                "temperature": 0.3,
                "max_tokens": 800
            },
            timeout=15
        )

        if response.status_code != 200:
            return {"error": f"Groq Error: {response.text}"}

        return json.loads(response.json()["choices"][0]["message"]["content"])

    except Exception as e:
        return {"error": str(e)}


# ---------------------------
# HEALTH CHECK
# ---------------------------
@app.get("/")
def home():
    return {
        "status": "AI backend running"
    }


# ---------------------------
# MAIN ENDPOINT
# ---------------------------
@app.post("/generate-ai-section")
def generate_ai_section(data: dict):

    print("INCOMING DATA:", data)

    section_name = data.get("sectionName")
    section_data = data.get("sectionData", {})

    expenses = section_data.get("expenses", [])
    revenue = section_data.get("revenue", [])
    company = section_data.get("company", {})
    members = section_data.get("members", [])
    teams = section_data.get("teams", [])

    metrics = {}

    # ---------------------------
    # EXPENSE CALCULATIONS
    # ---------------------------
    total_spending = 0

    if expenses:
        expense_df = pd.DataFrame(expenses)

        if "Amount" in expense_df.columns:
            expense_df["Amount"] = pd.to_numeric(
                expense_df["Amount"],
                errors="coerce"
            ).fillna(0)

            total_spending = float(
                expense_df["Amount"].sum()
            )

            metrics["total_spending"] = total_spending
            metrics["avg_spending"] = float(
                expense_df["Amount"].mean()
            )

            if "Category" in expense_df.columns:
                metrics["category_breakdown"] = (
                    expense_df.groupby("Category")["Amount"]
                    .sum()
                    .to_dict()
                )

            if "TeamName" in expense_df.columns:
                metrics["team_breakdown"] = (
                    expense_df[expense_df["TeamName"] != "general"]
                    .groupby("TeamName")["Amount"]
                    .sum()
                    .to_dict()
                )

            if "TeamMemberName" in expense_df.columns:
                metrics["member_breakdown"] = (
                    expense_df[expense_df["TeamMemberName"] != "none"]
                    .groupby("TeamMemberName")["Amount"]
                    .sum()
                    .to_dict()
                )

            if "ExpenseType" in expense_df.columns:
                metrics["expense_type_breakdown"] = (
                    expense_df.groupby("ExpenseType")["Amount"]
                    .sum()
                    .to_dict()
                )

            if "PaymentMethod" in expense_df.columns:
                metrics["payment_method_breakdown"] = (
                    expense_df.groupby("PaymentMethod")["Amount"]
                    .sum()
                    .to_dict()
                )

    # ---------------------------
    # REVENUE CALCULATIONS
    # ---------------------------
    total_revenue = 0

    if revenue:
        revenue_df = pd.DataFrame(revenue)

        if "Amount" in revenue_df.columns:
            revenue_df["Amount"] = pd.to_numeric(
                revenue_df["Amount"],
                errors="coerce"
            ).fillna(0)

            total_revenue = float(
                revenue_df["Amount"].sum()
            )

    metrics["total_revenue"] = total_revenue

    # ---------------------------
    # COMPANY DATA
    # ---------------------------
    funding = float(
        company.get("Funding", 0) or 0
    )

    runway = company.get(
        "Runway",
        "Unknown"
    )

    metrics["funding"] = funding
    metrics["runway"] = runway

    # ---------------------------
    # MEMBERS / TEAMS
    # ---------------------------
    metrics["team_count"] = len(teams)
    metrics["member_count"] = len(members)

    # ---------------------------
    # NET BURN
    # ---------------------------
    net_burn = total_spending - total_revenue
    metrics["net_burn"] = net_burn

    # ---------------------------
    # RISK
    # ---------------------------
    risk = "Low"

    if net_burn > 50000:
        risk = "Medium"

    if net_burn > 100000:
        risk = "High"

    metrics["risk"] = risk

    print("CALCULATED METRICS:", metrics)

    # ---------------------------
    # LLM PROMPT
    # ---------------------------
    
    section_map = {
        "main": """Return a JSON object. ALL strings must be ONE LINERS (MAX 6 WORDS). Use ONLY provided data:
{
  "primary_insight": "Cut ad spend now.",
  "high_impact_summary": "URGENT",
  "description": "Cancel unused software to save."
}""",
        "keyPoints": """Return a JSON object containing up to 3 key recommendations based ONLY on real data. ALL strings must be ONE LINERS (MAX 6 WORDS):
{
  "items": [
    {
      "title": "Cancel Figma",
      "description": "Not used for 3 months.",
      "savings": "$50/mo",
      "color": "#FF9F0A"
    }
  ]
}""",
        "runway": """Return a JSON object containing short runway opportunities based ONLY on real data. EACH MUST BE MAX 6 WORDS:
{
  "bullet_points": [
    "Reduce cloud costs.",
    "Pause hiring."
  ]
}""",
        "burn": """Return a JSON object containing up to 3 burn optimization items based ONLY on real data. ALL descriptions MUST BE MAX 6 WORDS:
{
  "items": [
    {
      "title": "AWS Bill",
      "description": "Downgrade unused server instances.",
      "savings": "$300/mo",
      "color": "#30D158"
    }
  ]
}""",
        "staffing": """Return a JSON object. Insight must be a ONE LINER (MAX 6 WORDS) based ONLY on real data:
{
  "insight": "Engineering costs are too high."
}""",
        "expense": """Return a JSON object. Insight must be a ONE LINER (MAX 6 WORDS) based ONLY on real data:
{
  "insight": "Marketing spend spiked this month."
}""",
        "subscription": """Return a JSON object containing up to 3 subscriptions based ONLY on real data. IF NO SUBSCRIPTIONS EXIST, RETURN 1 ITEM SAYING NO SUBSCRIPTIONS FOUND. ALL descriptions MUST BE MAX 6 WORDS:
{
  "items": [
    {
      "title": "No Subscriptions",
      "description": "No subscription data found.",
      "savings": "$0/mo",
      "color": "#FFFFFF"
    }
  ]
}"""
    }

    prompt_instruction = section_map.get(
        section_name, 
        """Return a JSON object with this exact structure:
{
  "insight": "Provide a brief analysis based on the metrics."
}"""
    )

    prompt = f"""
You are an AI CFO advisor for startups.
Analyze the following data and provide insights focused STRICTLY on the section: '{section_name}'.

Calculated Business Metrics:
{metrics}

CRITICAL: You must output ONLY valid JSON. Do not include markdown blocks or any other text.
{prompt_instruction}
"""

    result = call_llm(prompt)

    return {
        "status": "success",
        "metrics": metrics,
        "insight": result
    }

# ---------------------------
# CHAT ENDPOINT
# ---------------------------
@app.post("/chat")
def chat_endpoint(data: dict):
    question = data.get("question", "")
    section_data = data.get("sectionData", {})
    history = data.get("history", [])

    expenses = section_data.get("expenses", [])
    revenue = section_data.get("revenue", [])
    company = section_data.get("company", {})
    members = section_data.get("members", [])
    teams = section_data.get("teams", [])

    # Simple metrics
    total_spending = 0
    if expenses:
        expense_df = pd.DataFrame(expenses)
        if "Amount" in expense_df.columns:
            total_spending = float(pd.to_numeric(expense_df["Amount"], errors="coerce").fillna(0).sum())

    total_revenue = 0
    if revenue:
        revenue_df = pd.DataFrame(revenue)
        if "Amount" in revenue_df.columns:
            total_revenue = float(pd.to_numeric(revenue_df["Amount"], errors="coerce").fillna(0).sum())

    net_burn = total_spending - total_revenue
    funding = float(company.get("Funding", 0) or 0)
    runway = company.get("Runway", "Unknown")

    metrics_context = f"""
Summary Metrics:
Total Spending: ${total_spending}
Total Revenue: ${total_revenue}
Net Burn: ${net_burn}
Funding: ${funding}
Runway: {runway}

Detailed Data:
Company Details: {json.dumps(company)}
Expenses: {json.dumps(expenses)}
Members: {json.dumps(members)}
Teams: {json.dumps(teams)}
"""

    # Format history
    formatted_history = ""
    for msg in history:
        role = msg.get("role", "user")
        text = msg.get("text", "")
        formatted_history += f"{role.upper()}: {text}\\n"

    prompt = f"""
You are an AI Assistant for a startup founder. You have full access to their financial data below.
You MUST answer ANY question they ask.
CRITICAL RULES:
1. If they ask about their expenses, teams, or runway, use the Provided Data.
2. If they ask about competitors, general business advice, coding, or anything else NOT in the data, DO NOT say "I don't have this data". Instead, use your general world knowledge to answer the question as an expert advisor.
3. Keep your answer EXTREMELY short.
4. Use bullet points if applicable.

Provided Data:
{metrics_context}

Chat History:
{formatted_history}

USER QUESTION: {question}

Return a JSON object with this EXACT structure:
{{
  "response": "Your short answer here."
}}
"""
    result = call_llm(prompt)
    return {
        "status": "success",
        "response": result.get("response", "I could not generate an answer.")
    }