import requests

data = {
    "sectionName": "main",
    "sectionData": {
        "expenses": [{"Amount": 500, "Category": "software", "Type": "recurring"}],
        "company": {"Funding": 10000, "Runway": 12},
        "members": [],
        "teams": []
    },
    "currencySymbol": "₹"
}

res = requests.post("http://127.0.0.1:8000/generate-ai-section", json=data)
print(res.json())
