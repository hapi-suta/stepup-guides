# Build 01: FastAPI Model Server

FastAPI is a Python web framework built for APIs. It's fast, has automatic documentation, and handles input validation for you. This guide builds a model server from scratch.

---

## Step 1. Install FastAPI

On your **Mac terminal**, run:

```bash
pip3 install fastapi uvicorn
```

- `fastapi` is the web framework (defines your API endpoints)
- `uvicorn` is the ASGI server (actually runs the web server and handles HTTP connections)

DBA analogy: FastAPI is like your SQL logic. Uvicorn is like the PostgreSQL server process that listens on a port.

---

## Step 2. Build a minimal API

On your **Mac terminal**, run:

```bash
cat > /tmp/model_server.py << 'PYEOF'
from fastapi import FastAPI

# Create the FastAPI application
app = FastAPI(title="Alert Classifier API", version="1.0.0")
# FastAPI() creates the application object
# title and version appear in the auto-generated docs

# Health check endpoint
@app.get("/health")
def health_check():
    """Check if the server is running."""
    return {"status": "healthy"}
# @app.get("/health") is a "decorator" - it tells FastAPI:
#   "when someone sends GET /health, run this function"
# The function's return value is automatically converted to JSON

# Root endpoint
@app.get("/")
def root():
    """API information."""
    return {
        "name": "Alert Classifier API",
        "version": "1.0.0",
        "endpoints": ["/health", "/predict", "/docs"],
    }
PYEOF

echo "Server file created at /tmp/model_server.py"
echo "This is just the skeleton - we'll add the model next"
```

---

## Step 3. Add the classification model

On your **Mac terminal**, run:

```bash
cat > /tmp/model_server.py << 'PYEOF'
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
import time

# --- Pydantic Models (define request/response shapes) ---

# AlertRequest(BaseModel) means AlertRequest inherits from BaseModel.
# BaseModel (from Pydantic) auto-validates input data - if someone sends
# the wrong type, it rejects the request before your code runs.
# DBA analogy: like CHECK constraints on a table - data is validated on INSERT.
#
# Field(..., description="...") defines a required field with validation.
# The ... (Ellipsis) means "required, no default value."
# Optional[str] means "this field can be a string OR None."
# DBA analogy: ... = NOT NULL, Optional = nullable column.
class AlertRequest(BaseModel):
    """What the client sends to us."""
    message: str = Field(..., min_length=1, description="The alert message text")
    severity: str = Field(..., description="Alert severity: low, medium, high, critical")
    source: Optional[str] = Field(default="unknown", description="Alert source system")

# BaseModel is from Pydantic - it validates incoming data automatically
# Field(...) means "required" (the ... is Python's Ellipsis object)
# Field(default="unknown") means optional with a default
# min_length=1 rejects empty strings

class PredictionResponse(BaseModel):
    """What we send back to the client."""
    category: str
    confidence: float
    processing_time_ms: float
    model_version: str

class BatchRequest(BaseModel):
    """Multiple alerts at once."""
    alerts: List[AlertRequest]

class BatchResponse(BaseModel):
    """Multiple predictions at once."""
    predictions: List[PredictionResponse]
    total_time_ms: float
    count: int

# --- The Classifier ---

class AlertClassifier:
    """Keyword-based alert classifier (production would use ML model)."""

    def __init__(self):
        self.version = "1.0.0-keywords"
        self.categories = {
            "performance": ["cpu", "slow", "query", "latency", "timeout", "connection", "pool"],
            "storage": ["disk", "space", "full", "wal", "bloat", "tablespace", "storage"],
            "replication": ["replication", "standby", "lag", "wal sender", "primary", "failover"],
            "security": ["login", "unauthorized", "ssl", "password", "access", "denied", "certificate"],
            "backup": ["backup", "restore", "pg_dump", "pg_basebackup", "pitr", "wal archive"],
        }
        self.loaded_at = datetime.now().isoformat()

    def predict(self, message: str) -> tuple:
        """Classify an alert message. Returns (category, confidence)."""
        msg = message.lower()
        scores = {}
        for cat, keywords in self.categories.items():
            scores[cat] = sum(1 for kw in keywords if kw in msg)
            # Count how many keywords match for each category

        max_score = max(scores.values())
        if max_score > 0:
            category = max(scores, key=scores.get)
            confidence = min(1.0, max_score / 3)
            # Normalize: 1 keyword = 33%, 2 = 67%, 3+ = 100%
        else:
            category = "unknown"
            confidence = 0.0

        return category, confidence

# --- FastAPI Application ---

app = FastAPI(
    title="Alert Classifier API",
    version="1.0.0",
    description="Classifies database alerts into categories",
)

# Load model at startup (not per-request)
classifier = AlertClassifier()
# This runs once when the server starts
# The classifier stays in memory for all requests

# Health check
@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "model_version": classifier.version,
        "model_loaded_at": classifier.loaded_at,
    }

# Single prediction
@app.post("/predict", response_model=PredictionResponse)
def predict(request: AlertRequest):
    """Classify a single alert."""
    # Validate severity
    valid_severities = ["low", "medium", "high", "critical"]
    if request.severity not in valid_severities:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid severity '{request.severity}'. Must be one of {valid_severities}"
        )
    # HTTPException returns an error response with the given status code
    # 422 = Unprocessable Entity (valid JSON but bad values)

    # Run prediction
    start = time.time()
    category, confidence = classifier.predict(request.message)
    duration_ms = (time.time() - start) * 1000

    return PredictionResponse(
        category=category,
        confidence=round(confidence, 3),
        processing_time_ms=round(duration_ms, 3),
        model_version=classifier.version,
    )

# Batch prediction
@app.post("/predict/batch", response_model=BatchResponse)
def predict_batch(request: BatchRequest):
    """Classify multiple alerts at once."""
    start = time.time()
    predictions = []

    for alert in request.alerts:
        cat, conf = classifier.predict(alert.message)
        predictions.append(PredictionResponse(
            category=cat,
            confidence=round(conf, 3),
            processing_time_ms=0,  # individual times not tracked in batch
            model_version=classifier.version,
        ))

    total_ms = (time.time() - start) * 1000

    return BatchResponse(
        predictions=predictions,
        total_time_ms=round(total_ms, 3),
        count=len(predictions),
    )

# Model info
@app.get("/model/info")
def model_info():
    """Get information about the loaded model."""
    return {
        "version": classifier.version,
        "loaded_at": classifier.loaded_at,
        "categories": list(classifier.categories.keys()),
        "type": "keyword-based",
    }
PYEOF

echo "Full model server written to /tmp/model_server.py"
```

---

## Step 4. Run the server

On your **Mac terminal**, run:

```bash
cd /tmp && python3 -m uvicorn model_server:app --host 0.0.0.0 --port 8000 &
sleep 2
echo "Server started on http://localhost:8000"
```

- `uvicorn model_server:app` tells uvicorn: "in the file model_server.py, find the variable named app"
- `--host 0.0.0.0` means listen on all network interfaces (not just localhost)
- `--port 8000` is the port number
- `&` runs the server in the background so you can keep using the terminal

DBA analogy: This is like `pg_ctl start -D /pgdata -o '-p 5432'`

---

## Step 5. Test the API

On your **Mac terminal**, run:

```bash
# Health check
echo "=== Health Check ==="
curl -s http://localhost:8000/health | python3 -m json.tool
# curl sends an HTTP request
# -s means silent (no progress bar)
# python3 -m json.tool pretty-prints JSON

echo ""
echo "=== Single Prediction ==="
curl -s -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"message": "CPU usage exceeded 95% on pg-primary", "severity": "critical"}' \
  | python3 -m json.tool
# -X POST sends a POST request (not GET)
# -H sets a header (we're sending JSON)
# -d is the request body (the data)

echo ""
echo "=== Batch Prediction ==="
curl -s -X POST http://localhost:8000/predict/batch \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [
      {"message": "Replication lag 120 seconds", "severity": "high"},
      {"message": "Disk space at 92%", "severity": "medium"},
      {"message": "Failed login attempt from 10.0.0.99", "severity": "high"}
    ]
  }' | python3 -m json.tool

echo ""
echo "=== Invalid Request (should fail) ==="
curl -s -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"message": "", "severity": "critical"}' \
  | python3 -m json.tool
# Empty message should be rejected (min_length=1)

echo ""
echo "=== API Docs ==="
echo "Open http://localhost:8000/docs in your browser for interactive docs"
```

Expected output (yours will differ):

```
=== Health Check ===
{
    "status": "healthy",
    "model_version": "1.0.0-keywords",
    "model_loaded_at": "2024-01-15T10:30:00"
}

=== Single Prediction ===
{
    "category": "performance",
    "confidence": 0.333,
    "processing_time_ms": 0.05,
    "model_version": "1.0.0-keywords"
}
```

---

## Step 6. Test with Python

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import requests
import time

BASE_URL = "http://localhost:8000"

print("Testing Alert Classifier API with Python")
print("=" * 55)

# Test 1: Health check
r = requests.get(f"{BASE_URL}/health")
# requests.get() sends an HTTP GET request
print(f"Health: {r.json()['status']}")

# Test 2: Single predictions
test_alerts = [
    {"message": "CPU at 97% on pg-primary", "severity": "critical"},
    {"message": "Replication lag reached 120 seconds", "severity": "high"},
    {"message": "Disk space at 92% on /pgdata", "severity": "medium"},
    {"message": "SSL certificate expires in 3 days", "severity": "low"},
    {"message": "Slow query: 45s sequential scan on orders", "severity": "medium"},
    {"message": "pg_basebackup failed on standby", "severity": "high"},
]

print(f"\nSingle predictions ({len(test_alerts)} alerts):")
print(f"{'Category':>15s}  {'Conf':>5s}  {'ms':>6s}  Message")
print("-" * 70)

total_time = 0
for alert in test_alerts:
    start = time.time()
    r = requests.post(f"{BASE_URL}/predict", json=alert)
    # requests.post() sends POST with json= automatically setting Content-Type
    client_ms = (time.time() - start) * 1000
    total_time += client_ms

    pred = r.json()
    print(f"{pred['category']:>15s}  {pred['confidence']:>5.1%}  {client_ms:>5.1f}  {alert['message'][:40]}")

print(f"\nTotal client time: {total_time:.1f}ms for {len(test_alerts)} requests")
print(f"Average per request: {total_time / len(test_alerts):.1f}ms")

# Test 3: Batch prediction
print(f"\nBatch prediction (same {len(test_alerts)} alerts, one request):")
start = time.time()
r = requests.post(f"{BASE_URL}/predict/batch", json={"alerts": test_alerts})
batch_ms = (time.time() - start) * 1000

batch = r.json()
print(f"  {batch['count']} predictions in {batch['total_time_ms']:.1f}ms (server)")
print(f"  Client round-trip: {batch_ms:.1f}ms")
print(f"  Batch is {total_time / batch_ms:.1f}x faster than individual requests")
print(f"  (Less network overhead: 1 HTTP request instead of {len(test_alerts)})")
PYEOF
```

---

## Step 7. Stop the server

On your **Mac terminal**, run:

```bash
# Find and stop the uvicorn process
kill $(lsof -t -i:8000) 2>/dev/null
echo "Server stopped"
```

- `lsof -t -i:8000` finds the process ID using port 8000
- `kill` sends a termination signal to that process
- DBA analogy: like `pg_ctl stop -D /pgdata`

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| FastAPI | Python web framework for APIs | Like defining stored procedures |
| Pydantic models | Validate request/response data | Like CHECK constraints on columns |
| @app.post decorator | Register a function as an HTTP endpoint | Like CREATE FUNCTION |
| Model loading at startup | Load model once, use for all requests | Like shared_buffers loaded at pg start |
| uvicorn | ASGI server that runs FastAPI | Like the postgres server process |
| /docs endpoint | Auto-generated API documentation | Like pg_catalog for your API |
