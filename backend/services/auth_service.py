import firebase_admin
from firebase_admin import credentials, auth
from fastapi import HTTPException, Security, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import os
import concurrent.futures

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
            cred_path = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
            if cred_path and os.path.exists(cred_path):
                print(f"✅ Loading Firebase credentials explicitly from: {cred_path}")
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred, options={'projectId': 'startup-expense-tracker-3df6b'})
            else:
                print("⚠️  GOOGLE_APPLICATION_CREDENTIALS not set or file missing. Trying default auth...")
                firebase_admin.initialize_app(options={'projectId': 'startup-expense-tracker-3df6b'})
        _firebase_available = True
        print("✅ Firebase Admin initialized successfully.")
    except Exception as e:
        _firebase_available = False
        print(f"⚠️  Firebase Admin not available (dev mode will use token decoding): {e}")

def _verify_with_firebase(token: str):
    """Run Firebase token verification (may do network I/O for certs)."""
    decoded_token = auth.verify_id_token(token)
    return decoded_token['uid']

def verify_token(credentials: HTTPAuthorizationCredentials = Security(security), authorization: str = Header(None)):
    print(f"\n🔑 [AUTH] verify_token called")
    initialize_firebase()

    # Get token from either source
    token = None
    if credentials and credentials.credentials:
        token = credentials.credentials
    elif authorization and authorization.startswith("Bearer "):
        token = authorization.split("Bearer ")[1]

    if not token:
        print(f"🔑 [AUTH] No token provided!")
        raise HTTPException(status_code=401, detail="No authentication token provided.")

    # print(f"🔑 [AUTH] Token received (first 20 chars): {token[:20]}...") # Removed for security
    print(f"🔑 [AUTH] Firebase available: {_firebase_available}")

    # Try Firebase Admin verification first (production mode)
    # Use a thread with timeout to prevent hanging on cert download
    if _firebase_available:
        executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        try:
            print(f"🔑 [AUTH] Attempting Firebase token verification (10s timeout)...")
            future = executor.submit(_verify_with_firebase, token)
            uid = future.result(timeout=10)  # 10 second timeout
            print(f"🔑 [AUTH] Firebase verified UID: {uid}")
            return uid
        except concurrent.futures.TimeoutError:
            print(f"🔑 [AUTH] Firebase verification TIMED OUT — falling through to dev mode")
        except Exception as e:
            print(f"🔑 [AUTH] Firebase verification failed: {type(e).__name__}: {e}")
            pass  # Fall through to dev mode
        finally:
            executor.shutdown(wait=False)

    # Fallback to dev mode only if explicitly enabled
    if os.getenv("DEBUG_MODE", "false").lower() == "true":
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
            print(f"🔑 [AUTH] Dev mode also failed: {e}")
            raise HTTPException(status_code=401, detail=f"Invalid authentication credentials: {e}")
    else:
        raise HTTPException(status_code=401, detail="Authentication failed and dev mode is disabled.")
