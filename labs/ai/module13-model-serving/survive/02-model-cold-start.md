# Survive 02: Model Cold Start Catastrophe

Your model server container restarts after a crash. The model takes 45 seconds to load. During those 45 seconds, every request fails with a 503 error. Your alert routing system is blind - critical database alerts go unclassified and unrouted.

---

## The Disaster

On your **Mac terminal**, run the injection script:

```bash
python3 << 'PYEOF'
import time
from datetime import datetime

print("""
SCENARIO: Model Cold Start

Your model server container crashed at 02:47 AM.
Kubernetes restarted it automatically (good).
But the model takes 45 seconds to load into memory.

During those 45 seconds:
  - 73 requests came in
  - ALL 73 returned 503 "Service Unavailable"
  - 12 were critical severity alerts
  - 3 were "disk at 99%" that needed immediate routing to on-call
  - Those 3 alerts were never routed
  - A database ran out of disk at 03:15 AM
  - Nobody was paged until a user reported errors at 06:30 AM

Timeline:
  02:47:00  Container crashes (OOM)
  02:47:05  Kubernetes detects unhealthy container
  02:47:10  New container starts
  02:47:10  Model loading begins (45 seconds)
  02:47:55  Model loaded, server ready
  02:47:10 - 02:47:55  ALL REQUESTS FAIL (45 second blackout)
""")

# Simulate the cold start problem
class BrokenServer:
    """Server with cold start problem."""

    def __init__(self, load_time_seconds=3):
        self.model = None
        self.ready = False
        self.loading = True
        self.start_time = time.time()
        self.load_time = load_time_seconds

        # Simulate model loading
        print(f"  Server starting... model loading ({load_time_seconds}s)")

    def check_ready(self):
        if not self.ready and (time.time() - self.start_time) >= self.load_time:
            self.ready = True
            self.loading = False
            self.model = "loaded"
        return self.ready

    def predict(self, message):
        if not self.check_ready():
            return {"error": "503 Service Unavailable", "reason": "Model still loading"}
        return {"category": "performance", "confidence": 0.9}

# Simulate requests during cold start
server = BrokenServer(load_time_seconds=2)

print("\nRequests during cold start:")
print("-" * 55)

successes = 0
failures = 0

for i in range(20):
    result = server.predict(f"Alert {i}: CPU critical")
    if "error" in result:
        failures += 1
        if i < 5:  # show first few
            print(f"  [{i*0.15:.2f}s] Request {i+1}: 503 - Model still loading")
    else:
        successes += 1
        if successes <= 2:
            print(f"  [{i*0.15:.2f}s] Request {i+1}: OK - {result['category']}")
    time.sleep(0.15)

print(f"  ...")
print(f"\nResults: {failures} failed, {successes} succeeded")
print(f"All requests during the first ~2 seconds were dropped")
PYEOF
```

---

## Investigate

On your **Mac terminal**, understand the problem:

```bash
python3 << 'PYEOF'
print("""
Investigation: Why Cold Start Is Dangerous

Three problems combine:

1. MODEL LOAD TIME
   - Small models (keyword rules): < 1 second
   - Medium models (DistilBERT): 5-15 seconds
   - Large models (full BERT, GPT-2): 30-60 seconds
   - Very large models (LLaMA, etc): 2-5 minutes

   During load time, the server cannot serve predictions.

2. KUBERNETES HEALTH CHECKS
   - Kubernetes sends traffic to a pod as soon as it's "ready"
   - If your readiness probe just checks "is the process running?"
     it returns ready BEFORE the model is loaded
   - Traffic hits an unready server = errors

3. NO FALLBACK
   - When the model is loading, requests get 503 errors
   - Critical alerts during this window are lost
   - No fallback classifier, no queueing, nothing

DBA analogy:
   This is like PostgreSQL taking 5 minutes to start because it's
   recovering WAL. During recovery:
   - Connections are refused
   - Queries fail
   - If your app has no retry logic, requests are dropped

   PostgreSQL's fix: hot standby (serve reads during recovery)
   Model server fix: warm standby or fallback model
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
import time
import threading
from datetime import datetime

print("""
FIX: Three strategies to eliminate cold start impact.

Strategy 1: Proper readiness probe
  Don't report "ready" until the model is actually loaded.
  Kubernetes won't send traffic until the probe passes.

Strategy 2: Fallback model
  Use a lightweight model (keyword rules) during loading.
  It's less accurate but better than 503 errors.

Strategy 3: Pre-warming
  Keep a standby container with the model already loaded.
  On crash, traffic switches to the standby immediately.
""")

# Strategy 1: Proper readiness probe
print("Strategy 1: Proper Readiness Probe")
print("=" * 55)

class ServerWithReadinessProbe:
    def __init__(self):
        self.model = None
        self.loading = True
        self._start_loading()

    def _start_loading(self):
        """Load model in background thread."""
        def load():
            time.sleep(1)  # simulate model load
            self.model = "bert-classifier"
            self.loading = False
        threading.Thread(target=load, daemon=True).start()

    def readiness_probe(self):
        """Kubernetes calls this to check if we're ready for traffic."""
        if self.loading:
            return {"ready": False, "reason": "Model loading"}
            # Return False -> Kubernetes does NOT send traffic here
        return {"ready": True, "model": self.model}

    def predict(self, message):
        if self.loading:
            return {"error": "Not ready"}
        return {"category": "performance", "confidence": 0.9}

server1 = ServerWithReadinessProbe()

# Check readiness during loading
probe1 = server1.readiness_probe()
print(f"  During load: ready={probe1['ready']} ({probe1.get('reason', '')})")
print(f"  Kubernetes: NOT sending traffic (good)")

time.sleep(1.2)  # wait for load

probe2 = server1.readiness_probe()
print(f"  After load:  ready={probe2['ready']} (model={probe2.get('model', '')})")
print(f"  Kubernetes: NOW sending traffic")

# Strategy 2: Fallback model
print(f"\nStrategy 2: Fallback Model")
print("=" * 55)

class ServerWithFallback:
    """Use keyword rules while ML model loads."""

    def __init__(self):
        self.ml_model = None
        self.ml_loading = True
        self.requests_served_by_fallback = 0
        self.requests_served_by_model = 0
        self._start_loading()

    def _start_loading(self):
        def load():
            time.sleep(1)
            self.ml_model = "bert"
            self.ml_loading = False
        threading.Thread(target=load, daemon=True).start()

    def _fallback_classify(self, message):
        """Lightweight keyword classifier - always available."""
        msg = message.lower()
        if "cpu" in msg or "slow" in msg:
            return "performance", 0.6  # lower confidence (it's a fallback)
        elif "disk" in msg:
            return "storage", 0.6
        elif "replication" in msg:
            return "replication", 0.6
        return "unknown", 0.2

    def _ml_classify(self, message):
        """ML model classifier - better but needs loading."""
        msg = message.lower()
        if "cpu" in msg:
            return "performance", 0.95
        elif "disk" in msg:
            return "storage", 0.92
        return "unknown", 0.4

    def predict(self, message):
        if self.ml_loading:
            # Use fallback - degraded but functional
            cat, conf = self._fallback_classify(message)
            self.requests_served_by_fallback += 1
            return {"category": cat, "confidence": conf, "model": "fallback-rules"}
        else:
            cat, conf = self._ml_classify(message)
            self.requests_served_by_model += 1
            return {"category": cat, "confidence": conf, "model": "bert-classifier"}

server2 = ServerWithFallback()

# Requests during cold start
print("  Requests during model loading (fallback active):")
test_alerts = [
    "CPU at 99% on pg-primary",
    "Disk space at 98% on /pgdata",
    "Replication lag 300 seconds",
]

for msg in test_alerts:
    result = server2.predict(msg)
    print(f"    [{result['model']:>15s}] ({result['confidence']:.0%}) {msg[:40]}")

time.sleep(1.2)

# Requests after model loaded
print("\n  Requests after model loaded:")
for msg in test_alerts:
    result = server2.predict(msg)
    print(f"    [{result['model']:>15s}] ({result['confidence']:.0%}) {msg[:40]}")

print(f"\n  Fallback served: {server2.requests_served_by_fallback} requests (no 503s!)")
print(f"  ML model served: {server2.requests_served_by_model} requests")

# Strategy 3: Request queuing
print(f"\nStrategy 3: Request Queuing During Load")
print("=" * 55)

import queue

class ServerWithQueue:
    """Queue requests during cold start, process when ready."""

    def __init__(self):
        self.model = None
        self.loading = True
        self.pending = queue.Queue()
        self.results = []
        self._start_loading()

    def _start_loading(self):
        def load():
            time.sleep(0.5)
            self.model = "loaded"
            self.loading = False
            # Process queued requests
            processed = 0
            while not self.pending.empty():
                msg = self.pending.get()
                self.results.append({"message": msg, "category": "performance"})
                processed += 1
            print(f"    Model loaded! Processed {processed} queued requests")
        threading.Thread(target=load, daemon=True).start()

    def predict(self, message):
        if self.loading:
            self.pending.put(message)
            return {"status": "queued", "position": self.pending.qsize()}
        return {"status": "ok", "category": "performance"}

server3 = ServerWithQueue()

print("  Requests during loading (queued, not dropped):")
for i in range(5):
    result = server3.predict(f"Alert {i}: CPU critical")
    print(f"    Request {i+1}: {result['status']} (position: {result.get('position', 'N/A')})")

time.sleep(0.8)  # wait for model to load and process queue

print(f"\n  All {len(server3.results)} queued requests were processed after model loaded")
print(f"  Zero requests dropped, zero 503 errors")

print("""
Which strategy to use:

  Readiness probe: ALWAYS (minimum requirement)
    Prevents traffic before model is ready

  Fallback model: RECOMMENDED
    Serves degraded predictions during load (better than nothing)
    Best for alert classification (keyword rules are decent)

  Request queuing: SOMETIMES
    Good when clients can wait a few seconds
    Not good for real-time alerts (adds latency)

  Pre-warming / standby: FOR CRITICAL SYSTEMS
    Keep a second container with model loaded
    Instant failover, zero cold start
    Costs 2x resources (worth it for critical paths)

  DBA parallel:
    Readiness probe = pg_isready
    Fallback model = read from standby during primary restart
    Request queuing = pgbouncer queuing during failover
    Pre-warming = hot standby always ready for promotion
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Cold start | Requests fail during model load | Readiness probe + fallback model |
| Wrong readiness probe | Traffic sent before model ready | Check model.loaded, not just process.running |
| No fallback | 503 errors during loading | Lightweight keyword classifier as backup |
| No queuing | Requests during loading are lost | Queue and process after load completes |
| Single replica | One crash = total outage | Multiple replicas with rolling restart |
