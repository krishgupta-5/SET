import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate("app/startup-expense-tracker-3df6b-firebase-adminsdk-fbsvc-1a9a687e91.json")
firebase_admin.initialize_app(cred)

db = firestore.client()
users = db.collection('users').limit(1).get()
for u in users:
    print(u.id, u.to_dict())
