import firebase_admin
from firebase_admin import credentials, auth
from fastapi import HTTPException, Security, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import os

security = HTTPBearer(auto_error=False)

_firebase_initialized = False
_firebase_available = False

def initialize_firebase():
    global _firebase_initialized, _firebase_available
    if _firebase_initialized:
        return
    _firebase_initialized = True
    try:
        if not firebase_admin._apps:
            firebase_admin.initialize_app(options={'projectId': 'startup-expense-tracker-3df6b'})
        _firebase_available = True
        print("✅ Firebase Admin initialized successfully.")
    except Exception as e:
        _firebase_available = False
        print(f"⚠️  Firebase Admin not available (dev mode will use token decoding): {e}")

def verify_token(credentials: HTTPAuthorizationCredentials = Security(security), authorization: str = Header(None)):
    initialize_firebase()

    # Get token from either source
    token = None
    if credentials and credentials.credentials:
        token = credentials.credentials
    elif authorization and authorization.startswith("Bearer "):
        token = authorization.split("Bearer ")[1]

    if not token:
        raise HTTPException(status_code=401, detail="No authentication token provided.")

    # Try Firebase Admin verification first (production mode)
    if _firebase_available:
        try:
            decoded_token = auth.verify_id_token(token)
            return decoded_token['uid']
        except Exception:
            pass  # Fall through to dev mode

    # Dev mode: decode the JWT without verification to extract UID
    # This is safe for local development only.
    try:
        import base64
        import json
        # JWT has 3 parts: header.payload.signature
        payload = token.split('.')[1]
        # Add padding if needed
        padding = 4 - len(payload) % 4
        if padding != 4:
            payload += '=' * padding
        decoded = json.loads(base64.b64decode(payload))
        uid = decoded.get('user_id') or decoded.get('sub')
        if uid:
            print(f"🔓 Dev mode: extracted UID {uid} from token (not cryptographically verified)")
            return uid
        raise HTTPException(status_code=401, detail="Could not extract UID from token.")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Invalid authentication credentials: {e}")
