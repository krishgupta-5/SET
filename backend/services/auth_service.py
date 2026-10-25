import firebase_admin
from firebase_admin import credentials, auth
from fastapi import HTTPException, Security, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import os
import concurrent.futures

security = HTTPBearer(auto_error=False)


def _dev_mode() -> bool:
    """Unverified-token fallback is opt-in only (DEBUG_MODE=true, local dev).

    It used to default to true, which let anyone call the API as any user
    with no token or a forged one.
    """
    return os.getenv("DEBUG_MODE", "false").strip().lower() == "true"

_firebase_initialized = False
_firebase_available = False

def initialize_firebase():
    global _firebase_initialized, _firebase_available
    if _firebase_initialized:
        return
    _firebase_initialized = True
    try:
        if not firebase_admin._apps:
            raw_json = os.getenv('FIREBASE_CREDENTIALS_JSON')
            cred_path = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
            
            # 1. Direct JSON string in environment variable (Ideal for Render / Heroku)
            if raw_json and raw_json.strip():
                try:
                    import json
                    cred_dict = json.loads(raw_json.strip())
                    print("✅ Loading Firebase credentials from FIREBASE_CREDENTIALS_JSON environment variable")
                    cred = credentials.Certificate(cred_dict)
                    firebase_admin.initialize_app(cred, options={'projectId': 'startup-expense-tracker-3df6b'})
                    _firebase_available = True
                    return
                except Exception as e:
                    print(f"⚠️ Failed to parse FIREBASE_CREDENTIALS_JSON: {e}")

            # 2. Render Secret File path check
            if os.path.exists("/etc/secrets/firebase-adminsdk.json"):
                print("✅ Loading Firebase credentials from Render Secret File: /etc/secrets/firebase-adminsdk.json")
                cred = credentials.Certificate("/etc/secrets/firebase-adminsdk.json")
                firebase_admin.initialize_app(cred, options={'projectId': 'startup-expense-tracker-3df6b'})
                _firebase_available = True
                return

            # 3. Path specified in GOOGLE_APPLICATION_CREDENTIALS or auto-discovered
            found_path = None
            if cred_path and os.path.exists(cred_path):
                found_path = cred_path
            else:
                # Auto-discover service account in current dir, backend/, or app/
                import glob
                base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) # backend dir
                candidates = (
                    glob.glob(os.path.join(base_dir, "*firebase-adminsdk*.json")) +
                    glob.glob(os.path.join(base_dir, "firebase-adminsdk.json")) +
                    glob.glob(os.path.join(os.path.dirname(base_dir), "app", "*firebase-adminsdk*.json")) +
                    glob.glob("*firebase-adminsdk*.json")
                )
                if candidates:
                    found_path = candidates[0]

            if found_path and os.path.exists(found_path):
                print(f"✅ Loading Firebase credentials from: {found_path}")
                cred = credentials.Certificate(found_path)
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
        if _dev_mode():
            print("🔓 [AUTH] Dev mode: No token provided, using fallback dev-user-id")
            return "dev-user-id"
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
            print("🔑 [AUTH] Firebase verification timed out")
            if not _dev_mode():
                raise HTTPException(status_code=503, detail="Authentication service unavailable. Please retry.")
        except Exception as e:
            print(f"🔑 [AUTH] Firebase verification failed: {type(e).__name__}")
            if not _dev_mode():
                raise HTTPException(status_code=401, detail="Invalid or expired authentication token.")
        finally:
            executor.shutdown(wait=False)

    # Unverified decoding — local development only (DEBUG_MODE=true).
    if _dev_mode():
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
            print(f"🔑 [AUTH] Dev mode also failed: {type(e).__name__}")
            raise HTTPException(status_code=401, detail="Invalid authentication credentials.")
    else:
        raise HTTPException(status_code=401, detail="Authentication failed and dev mode is disabled.")
