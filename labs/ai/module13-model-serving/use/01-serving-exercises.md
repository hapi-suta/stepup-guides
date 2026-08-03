# Use 01: Model Serving Exercises

Practice building and testing model APIs.

---

## Exercise 1. Add a new endpoint

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from fastapi import FastAPI
from pydantic import BaseModel
from typing import List
import json

print("""
Exercise: Add a /stats endpoint that returns prediction statistics.

The endpoint should return:
  - Total predictions served
  - Average confidence
  - Category distribution (how many of each category)
  - Most common category

DBA analogy: like building a pg_stat_statements summary view
""")

# Simulate a prediction log
prediction_log = [
    {"category": "performance", "confidence": 0.92},
    {"category": "storage", "confidence": 0.85},
    {"category": "performance", "confidence": 0.88},
    {"category": "replication", "confidence": 0.91},
    {"category": "performance", "confidence": 0.95},
    {"category": "security", "confidence": 0.78},
    {"category": "storage", "confidence": 0.82},
    {"category": "performance", "confidence": 0.90},
    {"category": "replication", "confidence": 0.87},
    {"category": "unknown", "confidence": 0.15},
]

# YOUR TASK: compute stats from the prediction log
def compute_stats(predictions):
    """Compute prediction statistics."""
    total = len(predictions)
    if total == 0:
        return {"total": 0, "message": "No predictions yet"}

    # Average confidence
    avg_confidence = sum(p["confidence"] for p in predictions) / total

    # Category distribution
    from collections import Counter
    categories = Counter(p["category"] for p in predictions)
    # Counter counts occurrences: {"performance": 4, "storage": 2, ...}

    # Most common
    most_common = categories.most_common(1)[0]
    # .most_common(1) returns [(category, count)] - the top 1

    return {
        "total_predictions": total,
        "avg_confidence": round(avg_confidence, 3),
        "category_distribution": dict(categories),
        "most_common_category": most_common[0],
        "most_common_count": most_common[1],
    }

stats = compute_stats(prediction_log)

print("Prediction Stats:")
print("=" * 45)
for key, value in stats.items():
    if isinstance(value, dict):
        print(f"  {key}:")
        for k, v in value.items():
            print(f"    {k}: {v}")
    else:
        print(f"  {key}: {value}")

# Verify
assert stats["total_predictions"] == 10
assert stats["most_common_category"] == "performance"
assert 0 < stats["avg_confidence"] < 1
print("\nPASSED: Stats endpoint works correctly")
PYEOF
```

---

## Exercise 2. Request validation edge cases

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from pydantic import BaseModel, Field, field_validator
from typing import Optional

print("""
Exercise: Handle tricky validation edge cases.

Real-world APIs receive unexpected input:
  - Unicode characters
  - HTML/SQL injection attempts
  - Extremely long strings
  - Null bytes
  - Numbers where strings are expected
""")

class AlertRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=5000)
    severity: str = Field(...)
    source: Optional[str] = Field(default="unknown")

    @field_validator("message")
    @classmethod
    def clean_message(cls, v):
        # Strip whitespace
        v = v.strip()
        if not v:
            raise ValueError("Empty message after stripping whitespace")

        # Remove null bytes (can crash some systems)
        v = v.replace("\x00", "")
        # \x00 is the null byte character

        # Basic HTML tag removal (prevent XSS)
        import re
        v = re.sub(r"<[^>]+>", "", v)
        # re.sub replaces all matches of the pattern with ""
        # <[^>]+> matches anything between < and >

        if not v.strip():
            raise ValueError("Message is empty after cleaning")

        return v

    @field_validator("severity")
    @classmethod
    def validate_severity(cls, v):
        valid = ["low", "medium", "high", "critical"]
        v_lower = v.lower().strip()
        if v_lower not in valid:
            raise ValueError(f"Must be one of {valid}")
        return v_lower
        # Normalize to lowercase (accept "HIGH" -> "high")

# Test edge cases
test_cases = [
    ("Normal", {"message": "CPU at 95%", "severity": "high"}, True),
    ("Unicode", {"message": "CPU alerte 95%", "severity": "high"}, True),
    ("Case insensitive severity", {"message": "CPU high", "severity": "HIGH"}, True),
    ("HTML injection", {"message": "<script>alert('xss')</script>CPU high", "severity": "high"}, True),
    ("Null bytes", {"message": "CPU\x00 at 95%", "severity": "high"}, True),
    ("Only HTML tags", {"message": "<b></b>", "severity": "high"}, False),
    ("Only whitespace", {"message": "   \t\n  ", "severity": "high"}, False),
    ("Too long", {"message": "A" * 6000, "severity": "high"}, False),
]

print("Edge Case Validation:")
print("-" * 55)

for desc, data, should_pass in test_cases:
    try:
        req = AlertRequest(**data)
        passed = True
        msg_preview = req.message[:30]
    except Exception as e:
        passed = False
        msg_preview = str(e).split("\n")[1][:40] if "\n" in str(e) else str(e)[:40]

    status = "PASS" if passed == should_pass else "FAIL"
    result = "accepted" if passed else "rejected"
    print(f"  [{status}] {desc:<30s} -> {result}")

print("\nRobust validation handles the unexpected without crashing")
PYEOF
```

---

## Exercise 3. Load testing

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import statistics

print("""
Exercise: Measure your API's performance limits.

Key metrics:
  - Requests per second (throughput)
  - Latency per request (p50, p95, p99)
  - Error rate under load

DBA analogy: like pgbench measuring transactions per second
  pgbench -c 10 -j 2 -T 60 testdb
""")

# Simulate a model server's classify function
def classify(message):
    """Simulate model inference with ~1ms latency."""
    msg = message.lower()
    # Simulate some CPU work
    total = sum(ord(c) for c in msg)
    # ord(c) gets the ASCII code of each character
    # This is just to simulate a tiny amount of CPU work

    if "cpu" in msg:
        return "performance", 0.9
    elif "disk" in msg:
        return "storage", 0.85
    return "unknown", 0.3

# Load test: sequential requests
def run_load_test(num_requests, message="CPU at 95% on primary"):
    """Run N requests and measure performance."""
    latencies = []

    start_total = time.time()
    for i in range(num_requests):
        start = time.time()
        classify(message)
        latency_ms = (time.time() - start) * 1000
        latencies.append(latency_ms)
    total_time = time.time() - start_total

    # Calculate percentiles
    latencies.sort()
    p50 = latencies[len(latencies) // 2]
    p95 = latencies[int(len(latencies) * 0.95)]
    p99 = latencies[int(len(latencies) * 0.99)]

    return {
        "requests": num_requests,
        "total_time_s": round(total_time, 3),
        "rps": round(num_requests / total_time, 1),
        "p50_ms": round(p50, 3),
        "p95_ms": round(p95, 3),
        "p99_ms": round(p99, 3),
        "mean_ms": round(statistics.mean(latencies), 3),
    }

# Run tests at different loads
print("Load Test Results:")
print("=" * 65)
print(f"{'Requests':>10s}  {'Total(s)':>8s}  {'RPS':>8s}  {'p50(ms)':>8s}  {'p95(ms)':>8s}  {'p99(ms)':>8s}")
print("-" * 60)

for num in [100, 1000, 10000, 50000]:
    result = run_load_test(num)
    print(f"{result['requests']:>10d}  {result['total_time_s']:>8.3f}  "
          f"{result['rps']:>8.1f}  {result['p50_ms']:>8.3f}  "
          f"{result['p95_ms']:>8.3f}  {result['p99_ms']:>8.3f}")

print("""
Reading the results:
  - RPS (requests per second): how many predictions per second
  - p50: median latency (half of requests are faster than this)
  - p95: 95th percentile (95% of requests are faster)
  - p99: 99th percentile (only 1% are slower)

  p99 matters most - it's the worst experience your users see.

  Target for real-time alerts:
    p50 < 10ms, p95 < 50ms, p99 < 100ms

  If p99 >> p50, you have tail latency issues.
""")
PYEOF
```

---

## Exercise 4. Health check design

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
from datetime import datetime

print("""
Exercise: Design a comprehensive health check.

A good health check answers:
  1. Is the server running? (basic)
  2. Is the model loaded? (readiness)
  3. Can the model make predictions? (liveness)
  4. Are dependencies available? (deep)

DBA analogy:
  1. Is PostgreSQL process running? (pg_isready)
  2. Is it accepting connections? (can connect)
  3. Can it execute queries? (SELECT 1)
  4. Is replication working? (streaming state, lag)
""")

class HealthChecker:
    """Comprehensive health check system."""

    def __init__(self):
        self.model_loaded = True
        self.model_version = "v3"
        self.started_at = datetime.now()
        self.total_predictions = 1247
        self.total_errors = 3
        self.last_prediction_at = datetime.now()

    def basic_health(self):
        """Level 1: Is the server running?"""
        return {"status": "up", "timestamp": datetime.now().isoformat()}

    def readiness_check(self):
        """Level 2: Is the model loaded and ready to serve?"""
        checks = {
            "model_loaded": self.model_loaded,
            "model_version": self.model_version,
            "uptime_seconds": (datetime.now() - self.started_at).total_seconds(),
        }
        ready = all([self.model_loaded, self.model_version])
        # all() returns True if every element is truthy
        return {"ready": ready, "checks": checks}

    def liveness_check(self):
        """Level 3: Can the model actually make predictions?"""
        try:
            # Try a test prediction
            start = time.time()
            test_msg = "test CPU alert"
            msg = test_msg.lower()
            result = "performance" if "cpu" in msg else "unknown"
            latency_ms = (time.time() - start) * 1000

            return {
                "alive": True,
                "test_prediction": result,
                "test_latency_ms": round(latency_ms, 3),
            }
        except Exception as e:
            return {"alive": False, "error": str(e)}

    def deep_health(self):
        """Level 4: Full system health with dependencies."""
        error_rate = self.total_errors / max(self.total_predictions, 1) * 100

        return {
            "status": "healthy" if error_rate < 5 else "degraded",
            "basic": self.basic_health(),
            "readiness": self.readiness_check(),
            "liveness": self.liveness_check(),
            "metrics": {
                "total_predictions": self.total_predictions,
                "total_errors": self.total_errors,
                "error_rate_pct": round(error_rate, 2),
                "uptime_seconds": round((datetime.now() - self.started_at).total_seconds(), 1),
            },
        }

# Test
checker = HealthChecker()

print("Health Check Levels:")
print("=" * 55)

print("\nLevel 1 - Basic (for load balancer):")
print(f"  GET /health -> {checker.basic_health()}")

print("\nLevel 2 - Readiness (for Kubernetes):")
readiness = checker.readiness_check()
print(f"  GET /ready -> ready={readiness['ready']}")
for k, v in readiness["checks"].items():
    print(f"    {k}: {v}")

print("\nLevel 3 - Liveness (for monitoring):")
liveness = checker.liveness_check()
print(f"  GET /alive -> alive={liveness['alive']}, latency={liveness['test_latency_ms']}ms")

print("\nLevel 4 - Deep Health (for ops dashboard):")
deep = checker.deep_health()
print(f"  GET /health/deep -> status={deep['status']}")
print(f"    Predictions: {deep['metrics']['total_predictions']}")
print(f"    Errors: {deep['metrics']['total_errors']}")
print(f"    Error rate: {deep['metrics']['error_rate_pct']}%")

print("""
Which check for which use case:
  Load balancer: Level 1 (fast, just "is it up?")
  Kubernetes readiness probe: Level 2 (is it ready to serve?)
  Kubernetes liveness probe: Level 3 (can it do its job?)
  Ops dashboard: Level 4 (full system status)
""")
PYEOF
```

---

## Exercise 5. Graceful shutdown

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import signal
import time
import threading

print("""
Exercise: Handle server shutdown gracefully.

Problem: if you kill the server while it's processing requests,
  those requests get dropped (client gets connection reset).

Solution: graceful shutdown
  1. Stop accepting NEW requests
  2. Finish processing CURRENT requests
  3. Save any in-memory state
  4. Then exit

DBA analogy:
  pg_ctl stop -m smart   -> graceful (wait for clients to disconnect)
  pg_ctl stop -m fast    -> fast (rollback active transactions, then stop)
  pg_ctl stop -m immediate -> immediate (crash recovery on next start)

For a model server, you want "fast" - finish current requests, reject new ones.
""")

class GracefulServer:
    """Simulates a server with graceful shutdown."""

    def __init__(self):
        self.accepting_requests = True
        self.active_requests = 0
        self.total_served = 0
        self.lock = threading.Lock()
        # Lock prevents race conditions when multiple threads update counters

    def handle_request(self, request_id):
        """Process a request."""
        with self.lock:
            # with self.lock: acquires the lock, releases when block exits
            if not self.accepting_requests:
                return f"Request {request_id}: REJECTED (shutting down)"
            self.active_requests += 1

        # Simulate processing
        time.sleep(0.01)

        with self.lock:
            self.active_requests -= 1
            self.total_served += 1

        return f"Request {request_id}: OK"

    def shutdown(self, timeout=5):
        """Graceful shutdown."""
        print("\n  Shutdown initiated:")
        print("    1. Stop accepting new requests")
        self.accepting_requests = False

        print(f"    2. Waiting for {self.active_requests} active requests...")
        start = time.time()
        while self.active_requests > 0 and (time.time() - start) < timeout:
            time.sleep(0.1)

        if self.active_requests > 0:
            print(f"    3. Timeout! Force-closing {self.active_requests} requests")
        else:
            print("    3. All requests completed")

        print(f"    4. Server stopped (served {self.total_served} total requests)")

# Demo
server = GracefulServer()

print("Graceful Shutdown Demo:")
print("-" * 45)

# Simulate traffic
print("  Processing requests...")
for i in range(20):
    result = server.handle_request(i)
print(f"  Served {server.total_served} requests")

# Simulate shutdown while requests are in flight
# Start some "in-flight" requests in threads
threads = []
for i in range(5):
    t = threading.Thread(target=server.handle_request, args=(100 + i,))
    threads.append(t)
    t.start()

# Initiate shutdown
server.shutdown(timeout=5)

# Wait for threads
for t in threads:
    t.join()

print(f"\n  Final count: {server.total_served} requests served, 0 dropped")
print("  Graceful shutdown prevents data loss and client errors")
PYEOF
```

---

## What You Practiced

| Exercise | Skill | Production Use |
|----------|-------|---------------|
| Stats endpoint | Aggregate prediction metrics | Monitoring dashboard |
| Edge case validation | Handle unexpected input | Prevent crashes from bad data |
| Load testing | Measure performance limits | Capacity planning |
| Health check design | Multi-level health checks | Load balancer + Kubernetes probes |
| Graceful shutdown | Clean server stop | Zero-downtime deployments |
