# Build 02: Request Handling

Real-world APIs handle messy input, slow clients, and traffic bursts. This guide adds production-grade request handling: validation, async processing, rate limiting, and timeouts.

---

## Step 1. Input validation and error handling

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from pydantic import BaseModel, Field, field_validator
from typing import Optional
import json

print("""
Input Validation: Reject bad requests before they reach the model.

Why?
  - Bad input wastes compute (model inference is expensive)
  - Garbage in = garbage out (model returns meaningless predictions)
  - Unvalidated input can crash the server

DBA analogy:
  - CHECK constraints reject bad data at INSERT time
  - You don't let bad data into the table and then try to fix it later
""")

class AlertRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=5000)
    severity: str = Field(...)
    source: Optional[str] = Field(default="unknown", max_length=100)

    # @field_validator("field_name") runs this function to validate that specific field.
    # @classmethod means the function receives the class itself (cls) instead of an instance (self).
    # DBA analogy: @field_validator is like a CHECK constraint on a specific column.
    # cls is the table definition, not a row - used for validation logic that applies to all rows.
    @field_validator("severity")
    @classmethod
    def validate_severity(cls, v):
        """Check severity is a valid value."""
        valid = ["low", "medium", "high", "critical"]
        if v not in valid:
            raise ValueError(f"Must be one of {valid}, got '{v}'")
        return v
        # @field_validator runs automatically when creating the model
        # cls is the class itself (classmethod pattern)
        # v is the value of the field being validated
        # Raise ValueError to reject, return v to accept

    @field_validator("message")
    @classmethod
    def validate_message(cls, v):
        """Check message is not just whitespace."""
        if not v.strip():
            raise ValueError("Message cannot be empty or whitespace-only")
        if len(v.split()) < 2:
            raise ValueError("Message must contain at least 2 words")
        return v.strip()
        # .strip() removes leading/trailing whitespace
        # .split() splits on whitespace, giving word count

# Test validation
test_cases = [
    # (description, data, should_pass)
    ("Valid alert", {"message": "CPU at 95%", "severity": "critical"}, True),
    ("Empty message", {"message": "", "severity": "high"}, False),
    ("Whitespace only", {"message": "   ", "severity": "high"}, False),
    ("One word", {"message": "alert", "severity": "high"}, False),
    ("Bad severity", {"message": "CPU high", "severity": "urgent"}, False),
    ("Too long", {"message": "x" * 6000, "severity": "low"}, False),
    ("Valid with source", {"message": "Disk full now", "severity": "medium", "source": "nagios"}, True),
]

print("Input Validation Tests:")
print("-" * 55)

for desc, data, should_pass in test_cases:
    try:
        req = AlertRequest(**data)
        # **data unpacks the dict as keyword arguments
        # AlertRequest(message="CPU at 95%", severity="critical")
        passed = True
        detail = f"message='{req.message[:30]}'"
    except Exception as e:
        passed = False
        # Get first error message
        detail = str(e).split("\n")[1] if "\n" in str(e) else str(e)[:60]

    status = "PASS" if passed == should_pass else "FAIL"
    icon = "ok" if passed else "rejected"
    print(f"  [{status}] {desc:20s} -> {icon:10s} {detail[:50]}")

print("\nValidation catches bad input BEFORE it reaches the model")
PYEOF
```

---

## Step 2. Async request processing

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import asyncio
import time

print("""
Async Processing: Handle multiple requests without blocking.

Problem: If your server processes requests one at a time (synchronously),
  request 2 waits while request 1 is being processed.
  With 100ms inference time and 10 concurrent requests = 1 second wait for #10.

Solution: Use async/await for I/O operations (network, database).
  CPU-bound work (model inference) still blocks, but I/O doesn't.

DBA analogy:
  Sync:  one connection at a time (like max_connections = 1)
  Async: many connections at once (like max_connections = 100)
         Each query waits for disk I/O without blocking others
""")

# Synchronous version (blocking)
def process_sync(alerts):
    """Process alerts one at a time."""
    results = []
    for alert in alerts:
        time.sleep(0.05)  # simulate 50ms inference
        results.append({"message": alert, "category": "performance"})
    return results

# === ASYNC/AWAIT - WHAT YOU NEED TO KNOW ===
# async def = a function that can pause and let other code run while waiting.
# await = "pause here until this finishes, but let other requests proceed."
# Without async: 100 requests processed one at a time (slow).
# With async: 100 requests processed concurrently (fast).
# DBA analogy: sync = one psql session running queries one by one.
#              async = pgbouncer handling 100 connections to one database.
# asyncio.gather(*tasks) = run all tasks at the same time and wait for all to finish.
# The * unpacks the list so each task is a separate argument.

# Async version (non-blocking)
async def process_single(alert):
    """Process one alert asynchronously."""
    await asyncio.sleep(0.05)  # simulate 50ms I/O (non-blocking)
    # await asyncio.sleep() lets other tasks run while we wait
    # time.sleep() would block everything
    return {"message": alert, "category": "performance"}

async def process_async(alerts):
    """Process all alerts concurrently."""
    tasks = [process_single(alert) for alert in alerts]
    # Create a list of tasks (not executed yet)

    results = await asyncio.gather(*tasks)
    # asyncio.gather() runs all tasks concurrently
    # *tasks unpacks the list into individual arguments
    # It waits until ALL tasks are done, then returns all results
    return list(results)

# Compare
alerts = [f"Alert {i}" for i in range(20)]

# Sync
start = time.time()
sync_results = process_sync(alerts)
sync_time = time.time() - start

# Async
start = time.time()
async_results = asyncio.run(process_async(alerts))
# asyncio.run() starts the event loop and runs the async function
async_time = time.time() - start

print(f"Processing {len(alerts)} alerts:")
print(f"  Sync:  {sync_time*1000:.0f}ms (one at a time)")
print(f"  Async: {async_time*1000:.0f}ms (concurrent)")
print(f"  Speedup: {sync_time/async_time:.1f}x")

print("""
When to use async in a model server:
  - Database queries (fetching model config, logging predictions)
  - External API calls (sending alerts, webhooks)
  - File I/O (reading model files, writing logs)

When async DOESN'T help:
  - CPU-bound model inference (use multiple worker processes instead)
  - NumPy/PyTorch operations (these are already optimized)
""")
PYEOF
```

---

## Step 3. Rate limiting

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
from collections import defaultdict

print("""
Rate Limiting: Prevent clients from overwhelming the server.

Without rate limiting:
  - One client sends 10,000 requests/second
  - Server falls over, ALL clients affected
  - The equivalent of a denial-of-service attack

DBA analogy:
  - Like statement_timeout preventing runaway queries
  - Or pg_bouncer's max_client_conn limiting connections
  - One bad client shouldn't bring down the whole server
""")

class RateLimiter:
    """Simple sliding window rate limiter."""

    def __init__(self, max_requests: int, window_seconds: int):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.requests = defaultdict(list)
        # defaultdict(list) creates an empty list for new keys
        # Key = client ID, Value = list of request timestamps

    def is_allowed(self, client_id: str) -> tuple:
        """Check if a request is allowed. Returns (allowed, info)."""
        now = time.time()
        window_start = now - self.window_seconds

        # Remove old requests outside the window
        self.requests[client_id] = [
            t for t in self.requests[client_id] if t > window_start
        ]
        # List comprehension: keep only timestamps within the window

        current_count = len(self.requests[client_id])

        if current_count >= self.max_requests:
            # Calculate when they can retry
            oldest = min(self.requests[client_id])
            retry_after = oldest + self.window_seconds - now
            return False, {
                "error": "Rate limit exceeded",
                "limit": self.max_requests,
                "window_seconds": self.window_seconds,
                "current": current_count,
                "retry_after_seconds": round(retry_after, 1),
            }

        # Allow the request
        self.requests[client_id].append(now)
        remaining = self.max_requests - current_count - 1
        return True, {
            "remaining": remaining,
            "limit": self.max_requests,
            "window_seconds": self.window_seconds,
        }

# Demo
limiter = RateLimiter(max_requests=5, window_seconds=10)
# Allow 5 requests per 10-second window

print("Rate Limiter Demo (5 requests per 10 seconds):")
print("-" * 55)

# Client A: normal usage
print("\nClient A (normal):")
for i in range(3):
    allowed, info = limiter.is_allowed("client_a")
    status = "ALLOWED" if allowed else "BLOCKED"
    detail = f"remaining={info['remaining']}" if allowed else f"retry in {info['retry_after_seconds']}s"
    print(f"  Request {i+1}: {status} ({detail})")

# Client B: hammering the API
print("\nClient B (aggressive):")
for i in range(8):
    allowed, info = limiter.is_allowed("client_b")
    status = "ALLOWED" if allowed else "BLOCKED"
    if allowed:
        print(f"  Request {i+1}: {status} (remaining={info['remaining']})")
    else:
        print(f"  Request {i+1}: {status} (retry in {info['retry_after_seconds']}s)")

# Client A is unaffected by Client B's behavior
print("\nClient A (still fine):")
allowed, info = limiter.is_allowed("client_a")
status = "ALLOWED" if allowed else "BLOCKED"
print(f"  Request 4: {status} (remaining={info.get('remaining', 0)})")

print("\nRate limiting is per-client - one bad actor doesn't affect others")
print("In FastAPI, use the 'slowapi' or 'fastapi-limiter' package")
PYEOF
```

---

## Step 4. Request timeouts and graceful degradation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import asyncio

print("""
Timeouts: Don't let slow requests block the server forever.

Problem: a model inference hangs (bad input, GPU memory issue).
  Without timeout: the worker is stuck forever, one less worker available.
  With timeout: kill the request after N seconds, return an error.

DBA analogy: statement_timeout in PostgreSQL.
  SET statement_timeout = '5s';
  A query running longer than 5 seconds is cancelled.
""")

async def slow_inference(message):
    """Simulate a model that sometimes hangs."""
    if "complex" in message.lower():
        await asyncio.sleep(10)  # simulate hang
    else:
        await asyncio.sleep(0.05)  # normal inference
    return {"category": "performance", "confidence": 0.9}

async def predict_with_timeout(message, timeout_seconds=2.0):
    """Run inference with a timeout."""
    try:
        result = await asyncio.wait_for(
            slow_inference(message),
            timeout=timeout_seconds,
        )
        # asyncio.wait_for() wraps an async function with a timeout
        # If the function doesn't complete within timeout_seconds, it raises TimeoutError
        return {"status": "ok", "result": result}

    except asyncio.TimeoutError:
        # Inference took too long - return a fallback
        return {
            "status": "timeout",
            "result": {"category": "unknown", "confidence": 0.0},
            "message": f"Inference timed out after {timeout_seconds}s, returning fallback",
        }

# Test
print("Timeout Demo (2 second limit):")
print("-" * 55)

test_messages = [
    "CPU at 95% on primary",           # fast - completes normally
    "Complex nested query analysis",     # slow - will timeout
    "Disk space low on /pgdata",         # fast - completes normally
]

async def run_tests():
    for msg in test_messages:
        start = time.time()
        response = await predict_with_timeout(msg, timeout_seconds=2.0)
        elapsed = time.time() - start

        status = response["status"]
        cat = response["result"]["category"]
        print(f"  [{status:>7s}] {elapsed:.2f}s  [{cat:>13s}]  {msg[:40]}")

asyncio.run(run_tests())

print("""
Timeout strategy:
  1. Set inference timeout (e.g., 5 seconds)
  2. On timeout, return a fallback prediction (category="unknown")
  3. Log the timeout for investigation
  4. The client gets a response (degraded but fast) instead of waiting forever

This is "graceful degradation" - give a partial answer rather than no answer.
""")
PYEOF
```

---

## Step 5. Request logging and metrics

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import json
from collections import defaultdict
from datetime import datetime

print("""
Request Logging: Track every prediction for debugging and monitoring.

What to log:
  - Request: what was sent (message, severity)
  - Response: what was returned (category, confidence)
  - Performance: how long it took (latency_ms)
  - Metadata: when, client IP, model version

DBA analogy: pg_stat_statements tracks every query.
  You use it to find slow queries, popular queries, error rates.
  Request logging does the same for your model API.
""")

class RequestLogger:
    """Log and track API requests."""

    def __init__(self):
        self.logs = []
        self.metrics = {
            "total_requests": 0,
            "total_errors": 0,
            "latency_sum_ms": 0,
            "category_counts": defaultdict(int),
        }

    def log_request(self, request_data, response_data, latency_ms, error=None):
        """Log a single request."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "request": request_data,
            "response": response_data,
            "latency_ms": round(latency_ms, 2),
            "error": error,
        }
        self.logs.append(entry)

        # Update metrics
        self.metrics["total_requests"] += 1
        self.metrics["latency_sum_ms"] += latency_ms
        if error:
            self.metrics["total_errors"] += 1
        if response_data and "category" in response_data:
            self.metrics["category_counts"][response_data["category"]] += 1

    def get_metrics(self):
        """Get summary metrics."""
        total = self.metrics["total_requests"]
        if total == 0:
            return {"total_requests": 0}

        return {
            "total_requests": total,
            "total_errors": self.metrics["total_errors"],
            "error_rate": round(self.metrics["total_errors"] / total * 100, 1),
            "avg_latency_ms": round(self.metrics["latency_sum_ms"] / total, 2),
            "category_distribution": dict(self.metrics["category_counts"]),
        }

# Simulate API traffic
logger = RequestLogger()

# Simulate classify function
def classify(msg):
    msg = msg.lower()
    if "cpu" in msg or "slow" in msg:
        return "performance", 0.9
    elif "disk" in msg:
        return "storage", 0.8
    elif "replication" in msg:
        return "replication", 0.85
    return "unknown", 0.1

# Simulate requests
import random
random.seed(42)

requests_data = [
    ("CPU at 95% on primary", "critical"),
    ("Disk full on /pgdata", "high"),
    ("Replication lag 120s", "high"),
    ("Slow query on orders table", "medium"),
    ("Unknown system event", "low"),
    ("CPU spike on standby-2", "high"),
    ("", "critical"),  # bad request
    ("Disk at 88%", "medium"),
    ("Connection pool exhausted", "critical"),
    ("Replication failover started", "critical"),
]

print("Simulating API traffic (10 requests):")
print("-" * 60)

for msg, sev in requests_data:
    start = time.time()

    if not msg:
        latency = (time.time() - start) * 1000
        logger.log_request(
            {"message": msg, "severity": sev},
            None,
            latency,
            error="Empty message"
        )
        print(f"  [ERROR] Empty message")
        continue

    cat, conf = classify(msg)
    latency = (time.time() - start) * 1000 + random.uniform(1, 10)
    # Add simulated network latency

    logger.log_request(
        {"message": msg, "severity": sev},
        {"category": cat, "confidence": conf},
        latency,
    )
    print(f"  [{cat:>13s}] ({conf:.0%}) {latency:>5.1f}ms  {msg[:40]}")

# Show metrics
print(f"\nAPI Metrics:")
print("=" * 40)
metrics = logger.get_metrics()
for key, value in metrics.items():
    if key == "category_distribution":
        print(f"  {key}:")
        for cat, count in value.items():
            print(f"    {cat}: {count}")
    else:
        print(f"  {key}: {value}")

print("""
In production, send these metrics to:
  - Prometheus/Grafana for dashboards
  - CloudWatch/Datadog for alerts
  - PostgreSQL table for historical analysis
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Pydantic validators | Reject bad input before processing | CHECK constraints |
| Async processing | Handle multiple requests concurrently | Multiple connections |
| Rate limiting | Prevent client overload | max_client_conn in pgBouncer |
| Request timeout | Kill hung inference | statement_timeout |
| Graceful degradation | Return fallback instead of error | Read from replica when primary is down |
| Request logging | Track all predictions | pg_stat_statements |
