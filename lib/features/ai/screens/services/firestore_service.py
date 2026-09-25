from firebase_admin import firestore
import pandas as pd

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

def fetch_user_data(uid: str):
    db = get_firestore_client()
    if db is None:
        # Return empty data when Firestore is not available (dev mode without service account)
        print(f"⚠️  Firestore unavailable. Returning empty data for UID: {uid}")
        return {
            "expenses": [],
            "revenue": [],
            "company": {},
            "members": [],
            "teams": []
        }
    
    # Expenses (last 100 for context to save memory/tokens)
    expenses_ref = db.collection('expenses').where('uid', '==', uid).order_by('Date', direction=firestore.Query.DESCENDING).limit(100)
    expenses = [doc.to_dict() for doc in expenses_ref.stream()]
    
    # Revenue (last 100)
    revenue_ref = db.collection('revenue').where('uid', '==', uid).order_by('Date', direction=firestore.Query.DESCENDING).limit(100)
    revenue = [doc.to_dict() for doc in revenue_ref.stream()]
    
    # Companies
    companies_ref = db.collection('companies').where('uid', '==', uid).limit(1)
    companies = [doc.to_dict() for doc in companies_ref.stream()]
    company = companies[0] if companies else {}
    
    # Members
    members_ref = db.collection('members').where('uid', '==', uid)
    members = [doc.to_dict() for doc in members_ref.stream()]
    
    # Teams
    teams_ref = db.collection('teams').where('uid', '==', uid)
    teams = [doc.to_dict() for doc in teams_ref.stream()]

    return {
        "expenses": expenses,
        "revenue": revenue,
        "company": company,
        "members": members,
        "teams": teams
    }
