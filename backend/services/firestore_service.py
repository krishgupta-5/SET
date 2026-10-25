from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
import time
from datetime import datetime
from .metrics_service import to_datetime

# Hard ceiling per collection; well above realistic startup volumes.
MAX_DOCS = 5000

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
            # Keep the doc id: salary payments reference members by id, and
            # expenses reference teams by id.
            return [{**(doc.to_dict() or {}), "id": doc.id} for doc in query_ref.stream()]
        
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
    
    # All expenses: totals and runway are wrong if we only read a slice.
    # (An arbitrary .limit(100) without ordering used to drop random rows.)
    expenses = _safe_query(
        db.collection('expenses').where(filter=uid_filter).limit(MAX_DOCS),
        "expenses"
    )
    expenses.sort(key=lambda x: to_datetime(x.get('Date')) or datetime.min, reverse=True)

    revenue = _safe_query(
        db.collection('revenue').where(filter=uid_filter).limit(MAX_DOCS),
        "revenue"
    )
    revenue.sort(key=lambda x: to_datetime(x.get('Date')) or datetime.min, reverse=True)

    # Company doc id == uid (see company_setup_screen.dart); fall back to a query.
    company = {}
    try:
        snap = db.collection('companies').document(uid).get(timeout=15)
        if snap.exists:
            company = {**(snap.to_dict() or {}), "id": snap.id}
    except Exception as e:
        print(f"  ⚠️ [FIRESTORE] company doc read failed: {type(e).__name__}")
    if not company:
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
