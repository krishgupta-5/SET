from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
import pandas as pd
import time
import signal

_firestore_available = None

def get_firestore_client():
    global _firestore_available
    if _firestore_available is False:
        return None
    try:
        client = firestore.client()
        _firestore_available = True
        return client
    except Exception as e:
        _firestore_available = False
        print(f"⚠️  Firestore client not available: {e}")
        return None

def _safe_query(query_ref, label: str):
    """Execute a Firestore query with error handling and timeout."""
    try:
        start = time.time()
        print(f"  🔍 [FIRESTORE] Starting query: {label}...")
        import concurrent.futures
        
        def _run_query():
            return [doc.to_dict() for doc in query_ref.stream()]
        
        executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        future = executor.submit(_run_query)
        try:
            results = future.result(timeout=15)  # 15 second timeout per query
        except concurrent.futures.TimeoutError:
            print(f"  ⏰ [FIRESTORE] {label} query TIMED OUT (15s)! Returning empty.")
            return []
        finally:
            executor.shutdown(wait=False)
        
        elapsed = time.time() - start
        print(f"  📊 [FIRESTORE] {label}: {len(results)} docs in {elapsed:.2f}s")
        return results
    except Exception as e:
        print(f"  ⚠️ [FIRESTORE] {label} query failed: {type(e).__name__}: {e}")
        return []

def fetch_user_data(uid: str):
    print(f"\n📂 [FIRESTORE] Fetching data for UID: {uid}")
    db = get_firestore_client()
    if db is None:
        print(f"⚠️  Firestore unavailable. Returning empty data for UID: {uid}")
        return {
            "expenses": [],
            "revenue": [],
            "company": {},
            "members": [],
            "teams": []
        }
    
    # Use FieldFilter for all queries (avoids deprecation warning)
    uid_filter = FieldFilter('uid', '==', uid)
    
    # Expenses (last 100) — query WITHOUT order_by to avoid needing composite index
    # We'll sort in Python after fetching
    expenses = _safe_query(
        db.collection('expenses').where(filter=uid_filter).limit(100),
        "expenses"
    )
    # Sort by Date in Python (descending) if Date field exists
    if expenses:
        try:
            expenses.sort(key=lambda x: x.get('Date', ''), reverse=True)
        except Exception:
            pass  # If dates aren't sortable, keep original order
    
    # Revenue (last 100) — same approach, no order_by
    revenue = _safe_query(
        db.collection('revenue').where(filter=uid_filter).limit(100),
        "revenue"
    )
    if revenue:
        try:
            revenue.sort(key=lambda x: x.get('Date', ''), reverse=True)
        except Exception:
            pass
    
    # Companies
    companies = _safe_query(
        db.collection('companies').where(filter=uid_filter).limit(1),
        "companies"
    )
    company = companies[0] if companies else {}
    
    # Members
    members = _safe_query(
        db.collection('members').where(filter=uid_filter),
        "members"
    )
    
    # Teams
    teams = _safe_query(
        db.collection('teams').where(filter=uid_filter),
        "teams"
    )

    print(f"📂 [FIRESTORE] Fetch complete: {len(expenses)} expenses, {len(revenue)} revenue, company={'yes' if company else 'no'}, {len(members)} members, {len(teams)} teams")

    return {
        "expenses": expenses,
        "revenue": revenue,
        "company": company,
        "members": members,
        "teams": teams
    }
