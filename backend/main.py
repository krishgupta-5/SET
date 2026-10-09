import socket
old_getaddrinfo = socket.getaddrinfo
def new_getaddrinfo(*args, **kwargs):
    responses = old_getaddrinfo(*args, **kwargs)
    return [response for response in responses if response[0] == socket.AF_INET]
socket.getaddrinfo = new_getaddrinfo

from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import requests
import os
import pandas as pd
import json
import time
from dotenv import load_dotenv

from services.auth_service import verify_token
from services.chat_service import process_chat_message, process_chat_message_stream
from services.cache_service import clear_cache
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse

load_dotenv()

app = FastAPI(title="AI CFO Backend")

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request, exc):
    return JSONResponse(
        status_code=400,
        content={"detail": str(exc)},
    )

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
def call_llm(prompt, retries=3):
    for attempt in range(retries):
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

            if response.status_code == 429: # Rate Limit
                time.sleep(2 ** attempt)
                continue

            if response.status_code != 200:
                print(f"LLM API Error: {response.text}")
                return {"error": f"API Error: {response.text}"}

            content = response.json()["choices"][0]["message"]["content"]
            
            # Clean markdown codeblocks
            content = content.strip()
            if content.startswith("```json"):
                content = content[7:]
            elif content.startswith("```"):
                content = content[3:]
            if content.endswith("```"):
                content = content[:-3]
                
            return json.loads(content.strip())

        except Exception as e:
            if attempt == retries - 1:
                print(f"LLM Parsing Error: {e}")
                return {"error": str(e)}
            time.sleep(1)


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
def generate_ai_section(data: dict, uid: str = Depends(verify_token)):

    # print(f"INCOMING DATA (uid={uid}):", data) # Removed for security

    section_name = data.get("sectionName")
    section_data = data.get("sectionData", {})
    currency_symbol = data.get("currencySymbol", "$")

    expenses = section_data.get("expenses", [])
    revenue = section_data.get("revenue", [])
    company = section_data.get("company", {})
    members = section_data.get("members", [])
    teams = section_data.get("teams", [])

    metrics = {}
    metrics["currency_symbol"] = currency_symbol

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
    
    cs = currency_symbol  # shorthand for prompt templates

    section_map = {
        "main": f"""Return a JSON object using this EXACT structure as an EXAMPLE, but REPLACE the values with real insights based ONLY on provided data. The description should be detailed (1-2 sentences, 15-25 words) to explain the 'why' and 'how'. Use {cs} as the currency symbol:
{{
  "primary_insight": "E.g. Cut cloud infrastructure costs to extend runway.",
  "high_impact_summary": "E.g. HIGH CLOUD SPEND",
  "description": "E.g. Your cloud infrastructure costs have become your largest expense this month. Consider canceling unused servers and migrating to reserved instances to save money."
}}""",
        "keyPoints": f"""Return a JSON object containing up to 3 key recommendations based ONLY on real data. Use this structure as an EXAMPLE and REPLACE the values. Titles should be short, but descriptions MUST be detailed (1-2 sentences, 15-25 words) explaining the recommendation. Use {cs} as the currency symbol:
{{
  "items": [
    {{
      "title": "E.g. Cancel Figma Subscription",
      "description": "E.g. This tool hasn't been actively used by your design team for over 3 months. Canceling it now will immediately free up monthly cash flow.",
      "savings": "E.g. {cs}50/mo",
      "color": "#FF9F0A"
    }}
  ]
}}""",
        "runway": f"""Return a JSON object containing short runway opportunities based ONLY on real data. Use this structure as an EXAMPLE and REPLACE the values. Bullet points should be actionable and detailed (10-20 words each). Use {cs} as the currency symbol:
{{
  "bullet_points": [
    "E.g. Reduce your monthly cloud infrastructure costs by auditing and removing unused AWS environments.",
    "E.g. Pause all non-essential hiring for the next quarter to ensure your runway extends beyond 12 months."
  ]
}}""",
        "burn": f"""Return a JSON object containing up to 3 burn optimization items based ONLY on real data. If there is historical burn data over time, you can optionally include a 'chart_type' of "bar" and a 'chart_data' array to visualize the trend. Use this structure as an EXAMPLE and REPLACE the values. Descriptions MUST be detailed (1-2 sentences, 15-25 words) explaining the optimization. Use {cs} as the currency symbol:
{{
  "items": [
    {{
      "title": "E.g. AWS Server Bill",
      "description": "E.g. You can downgrade your staging servers to cheaper tiers during the weekends when they are not in active use by the engineering team.",
      "savings": "E.g. {cs}300/mo",
      "color": "#30D158"
    }}
  ],
  "chart_type": "bar",
  "chart_data": [
    {{"label": "Jul", "value": 15000, "color": "#FF9F0A"}},
    {{"label": "Aug", "value": 12000, "color": "#FF9F0A"}},
    {{"label": "Sep", "value": 9000, "color": "#FF9F0A"}}
  ]
}}""",
        "staffing": f"""Return a JSON object. The insight must be a detailed analysis (1-2 sentences, 15-25 words) based ONLY on real data. Use this structure as an EXAMPLE and REPLACE the values. Use {cs} as the currency symbol:
{{
  "insight": "E.g. Your engineering costs have risen significantly over the past quarter. Consider utilizing more freelance contractors for short-term projects instead of full-time hires."
}}""",
        "expense": f"""Return a JSON object. The insight must be a detailed analysis (1-2 sentences, 15-25 words) based ONLY on real data. If there are at least 2 expense categories, include a 'chart_type' of "pie" and 'chart_data' array. Use this structure as an EXAMPLE and REPLACE the values. Use {cs} as the currency symbol:
{{
  "insight": "E.g. Software expenses dominate at {cs}500, while marketing is minimal. Consider reallocating to high-impact areas.",
  "chart_type": "pie",
  "chart_data": [
    {{"label": "Software", "value": 500, "color": "#0A84FF"}},
    {{"label": "Marketing", "value": 100, "color": "#FF453A"}}
  ]
}}""",
        "subscription": f"""Return a JSON object containing up to 3 subscriptions based ONLY on real data. IF NO SUBSCRIPTIONS EXIST, RETURN 1 ITEM SAYING NO SUBSCRIPTIONS FOUND. Use this structure as an EXAMPLE and REPLACE the values. Descriptions MUST be detailed (1-2 sentences, 15-25 words). Use {cs} as the currency symbol:
{{
  "items": [
    {{
      "title": "E.g. No Subscriptions",
      "description": "E.g. We couldn't find any recurring subscription data in your recent expenses. Make sure to categorize your software tools correctly so we can analyze them.",
      "savings": "E.g. {cs}0/mo",
      "color": "#FFFFFF"
    }}
  ]
}}"""
    }

    prompt_instruction = section_map.get(
        section_name, 
        f"""Return a JSON object with this exact structure as an EXAMPLE, and REPLACE the values based on data. Use {cs} as the currency symbol:
{{
  "insight": "E.g. Provide a brief analysis."
}}"""
    )

    # Build data availability context for the LLM
    has_data = total_spending > 0 or total_revenue > 0 or len(members) > 0
    data_context = ""
    if not has_data:
        data_context = f"""\nIMPORTANT: The user has NO expenses, NO revenue, and NO team members recorded yet.
You MUST NOT invent or hallucinate any numbers, categories, or recommendations.
Return a helpful message telling the user to add data first.
For sections with "items", return 1 item with title "No data yet", description "Add expenses to get insights.", savings "{cs}0/mo", color "#8E8E93".
For sections with "insight", return "Add expenses to get started."
For sections with "bullet_points", return ["Add expenses to get started."].
For sections with "primary_insight", return the exact JSON: {{"primary_insight": "Welcome to AI Insights", "high_impact_summary": "ADD DATA", "description": "Add expenses to get started."}}.
"""

    prompt = f"""
You are an AI CFO advisor for startups.
Analyze the following data and provide insights focused STRICTLY on the section: '{section_name}'.

Calculated Business Metrics:
{metrics}

CURRENCY: Always use {cs} as the currency symbol. Never use $ or any other symbol.
{data_context}
CRITICAL INSTRUCTIONS:
1. You must output ONLY valid JSON. Do not include markdown blocks or any other text.
2. You MUST NOT invent, hallucinate, or make hypothetical assumptions about numbers, expenses, or any data. If data is missing or insufficient, you MUST STILL return the EXACT requested JSON structure, but use safe fallback text (e.g. 'Insufficient data to analyze') or 0 for the values. Do not make up fake values.
3. Base your primary insights on the actual data provided, but expand on it for actionable advice.
4. All monetary values must use the exact '{cs}' symbol. NEVER use '$' unless '{cs}' is '$'.

{prompt_instruction}
"""

    result = call_llm(prompt)

    return {
        "status": "success",
        "metrics": metrics,
        "insight": result
    }

# ---------------------------
# CHAT ENDPOINT (REFACTORED)
# ---------------------------
class ChatRequest(BaseModel):
    question: str
    sessionId: Optional[str] = None
    history: List[Dict[str, Any]] = []
    sectionData: Optional[Dict[str, Any]] = None
    currencySymbol: str = "$"

@app.post("/chat")
def chat_endpoint(request: ChatRequest, uid: str = Depends(verify_token)):
    answer = process_chat_message(uid, request.question, request.history, request.sectionData, request.currencySymbol)
    return {
        "status": "success",
        "response": answer
    }

@app.post("/chat/stream")
def chat_endpoint_stream(request: ChatRequest, uid: str = Depends(verify_token)):
    return StreamingResponse(
        process_chat_message_stream(uid, request.question, request.history, request.sectionData, request.currencySymbol),
        media_type="text/event-stream"
    )

@app.post("/ai/context/invalidate")
def invalidate_ai_context(uid: str = Depends(verify_token)):
    clear_cache(uid)
    return {"status": "success"}