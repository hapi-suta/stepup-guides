# Use 01: Pipeline Exercises

Practice building and debugging AI pipelines.

---

## Exercise 1. Add a new pipeline stage

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from dataclasses import dataclass, field
from typing import Optional
from datetime import datetime

@dataclass
class PipelineResult:
    success: bool
    data: object = None
    error: Optional[str] = None
    stage: str = ""

# YOUR TASK: Build a "deduplicate" stage
# It should:
#   1. Accept a list of alerts (dicts with "message" key)
#   2. Remove alerts with duplicate messages (keep first occurrence)
#   3. Return PipelineResult with deduplicated list

# Hint: use a set to track seen messages

def deduplicate(alerts):
    """Remove duplicate alerts based on message content."""
    seen = set()
    # set() is like a hash table with only keys, no values
    # Lookup is O(1), same as checking if a key exists in a dict

    unique = []
    for alert in alerts:
        msg = alert["message"].lower().strip()
        if msg not in seen:
            seen.add(msg)
            unique.append(alert)
        # If msg is already in seen, we skip it (duplicate)

    return PipelineResult(
        success=True,
        data=unique,
        stage="deduplicate"
    )

# Test it
alerts = [
    {"message": "CPU at 95%", "severity": "critical"},
    {"message": "Disk full", "severity": "high"},
    {"message": "cpu at 95%", "severity": "high"},       # duplicate (case-insensitive)
    {"message": "  Disk full  ", "severity": "medium"},   # duplicate (extra whitespace)
    {"message": "Replication lag 60s", "severity": "high"},
]

result = deduplicate(alerts)
print(f"Input: {len(alerts)} alerts")
print(f"After dedup: {len(result.data)} alerts")
print(f"Removed: {len(alerts) - len(result.data)} duplicates")
print()
for a in result.data:
    print(f"  [{a['severity']:>8s}] {a['message']}")

# Verify
assert len(result.data) == 3, f"Expected 3, got {len(result.data)}"
assert result.success == True
print("\nPASSED: Deduplication stage works correctly")
PYEOF
```

---

## Exercise 2. Retry with jitter

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import random

random.seed(42)

# YOUR TASK: Add "jitter" to retry backoff
# Problem: if 100 clients all retry at the same time (after the same delay),
#   they all hit the server again at once. This is called "thundering herd."
# Solution: add random jitter so retries are spread out.
#
# Without jitter: delay = base * 2^attempt       (all clients retry together)
# With jitter:    delay = random(0, base * 2^attempt)  (clients retry at random times)
#
# DBA analogy: like adding random delay to prevent all cron jobs from running at :00

def retry_with_jitter(func, max_retries=3, base_delay=1.0):
    """Retry with exponential backoff AND jitter."""
    for attempt in range(max_retries + 1):
        try:
            return func()
        except Exception as e:
            if attempt == max_retries:
                raise

            max_delay = base_delay * (2 ** attempt)
            # max_delay grows: 1, 2, 4, 8...

            jitter_delay = random.uniform(0, max_delay)
            # random.uniform(a, b) returns a random float between a and b
            # This spreads retries across the full delay window

            print(f"  Attempt {attempt + 1} failed. "
                  f"Max delay: {max_delay:.1f}s, Actual delay: {jitter_delay:.2f}s")
            time.sleep(jitter_delay * 0.01)  # shortened for demo

# Test: simulate 5 clients all retrying
print("Retry with Jitter (5 clients):")
print("-" * 55)

for client in range(5):
    random.seed(client)  # different seed per client
    call_count = 0

    def flaky_api():
        global call_count
        call_count += 1
        if random.random() < 0.7:
            raise ConnectionError("timeout")
        return "ok"

    print(f"\nClient {client + 1}:")
    try:
        retry_with_jitter(flaky_api, max_retries=4)
        print(f"  Succeeded after {call_count} calls")
    except ConnectionError:
        print(f"  Failed after {call_count} calls")

print("\nJitter prevents thundering herd - retries are spread out over time")
PYEOF
```

---

## Exercise 3. Pipeline with fallback

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Fallback Pattern: If the primary method fails, use a backup.

DBA analogy:
  Primary: read from primary database
  Fallback: read from read replica
  Last resort: serve stale cache

AI pipeline:
  Primary: classify with ML model
  Fallback: classify with keyword rules
  Last resort: mark as "unknown" for manual review
""")

def classify_with_model(message):
    """Simulate ML model classification (sometimes fails)."""
    # Simulate model being unavailable
    if "error" in message.lower():
        raise RuntimeError("Model service unavailable")
    return {"category": "model_result", "confidence": 0.95, "method": "ml_model"}

def classify_with_rules(message):
    """Rule-based fallback classification."""
    msg = message.lower()
    if any(w in msg for w in ["cpu", "slow", "query"]):
        cat = "performance"
    elif any(w in msg for w in ["disk", "space", "full"]):
        cat = "storage"
    elif any(w in msg for w in ["replication", "lag"]):
        cat = "replication"
    else:
        cat = "unknown"
    return {"category": cat, "confidence": 0.6, "method": "rules"}

def classify_with_fallback(message):
    """Try model first, fall back to rules, then unknown."""
    # Try primary (ML model)
    try:
        return classify_with_model(message)
    except Exception as e:
        print(f"    Model failed: {e}")

    # Try fallback (rules)
    try:
        return classify_with_rules(message)
    except Exception as e:
        print(f"    Rules failed: {e}")

    # Last resort
    return {"category": "unknown", "confidence": 0.0, "method": "default"}

# Test
alerts = [
    "CPU at 95% on primary server",
    "Model error: connection refused",
    "Disk space critically low",
    "Replication lag increasing",
]

print("Classification with Fallback:")
print("-" * 60)

for msg in alerts:
    result = classify_with_fallback(msg)
    print(f"  [{result['method']:>10s}] ({result['confidence']:.0%}) {msg[:40]}")

print()
print("Fallback ensures the pipeline never stops completely")
print("Degraded service is better than no service")
PYEOF
```

---

## Exercise 4. DLQ replay

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime

print("""
DLQ Replay: Reprocess failed items after fixing the root cause.

Workflow:
  1. Items fail processing -> saved to DLQ
  2. You investigate and fix the bug
  3. Replay DLQ items through the (now fixed) pipeline
  4. Items that still fail go back to DLQ

DBA analogy: like retrying failed rows after fixing a constraint issue
  UPDATE failed_rows SET status = 'pending' WHERE error = 'fixed_bug';
""")

dlq_file = "/tmp/dlq_replay_demo.jsonl"

# Simulate: some items failed earlier
failed_items = [
    {"id": 1, "message": "", "error": "Empty message", "failed_at": "2024-01-15T10:00:00"},
    {"id": 2, "message": "CPU at 99%", "severity": "urgent", "error": "Invalid severity", "failed_at": "2024-01-15T10:01:00"},
    {"id": 3, "message": None, "error": "Null message", "failed_at": "2024-01-15T10:02:00"},
    {"id": 4, "message": "Disk full", "severity": "critical", "error": "Missing source field", "failed_at": "2024-01-15T10:03:00"},
]

# Write to DLQ
with open(dlq_file, "w") as f:
    for item in failed_items:
        f.write(json.dumps(item) + "\n")

print(f"DLQ has {len(failed_items)} failed items\n")

# "Fix" the pipeline: now we handle edge cases better
def process_fixed(item):
    """Improved processing that handles more edge cases."""
    # Fix 1: handle empty/null messages
    if not item.get("message"):
        return None, "Still no message - needs manual fix"

    # Fix 2: map non-standard severities
    severity_map = {"urgent": "critical", "warn": "medium", "info": "low"}
    # If severity is non-standard, try to map it
    sev = item.get("severity", "medium")
    sev = severity_map.get(sev, sev)
    # .get(sev, sev) returns the mapped value if found, otherwise keeps original

    if sev not in ["low", "medium", "high", "critical"]:
        return None, f"Cannot map severity: {sev}"

    # Fix 3: add missing fields with defaults
    return {
        "id": item["id"],
        "message": item["message"],
        "severity": sev,
        "source": item.get("source", "unknown"),
        "reprocessed_at": datetime.now().isoformat(),
    }, None

# Replay DLQ
print("Replaying DLQ with fixed pipeline:")
print("-" * 55)

recovered = []
still_failed = []

with open(dlq_file) as f:
    for line in f:
        item = json.loads(line)
        result, error = process_fixed(item)

        if result:
            recovered.append(result)
            print(f"  [RECOVERED] id={item['id']}  {result['message'][:30]}")
        else:
            still_failed.append({"item": item, "error": error})
            print(f"  [STILL BAD] id={item['id']}  {error}")

print(f"\nRecovered: {len(recovered)}/{len(failed_items)}")
print(f"Still failed: {len(still_failed)}/{len(failed_items)}")

# Write remaining failures back to DLQ
with open(dlq_file, "w") as f:
    for entry in still_failed:
        f.write(json.dumps(entry) + "\n")

print(f"\nUpdated DLQ: {len(still_failed)} items remaining")
print("Items that still fail need manual investigation")
PYEOF
```

---

## Exercise 5. End-to-end pipeline with monitoring

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import time
import random
from datetime import datetime
from collections import defaultdict

random.seed(42)

print("""
Build a complete pipeline with:
  1. Ingest -> Validate -> Classify -> Store
  2. Retry logic on transient failures
  3. Dead letter queue for permanent failures
  4. Monitoring metrics per stage
""")

# Monitoring
metrics = defaultdict(lambda: {"ok": 0, "fail": 0, "ms": 0})

def record(stage, ok, ms):
    key = "ok" if ok else "fail"
    metrics[stage][key] += 1
    metrics[stage]["ms"] += ms

# DLQ
dlq = []

# Pipeline stages
def ingest(raw):
    start = time.time()
    if not isinstance(raw, dict):
        record("ingest", False, (time.time() - start) * 1000)
        return None, "Not a dict"
    record("ingest", True, (time.time() - start) * 1000)
    return raw, None

def validate(alert):
    start = time.time()
    if not alert.get("message", "").strip():
        record("validate", False, (time.time() - start) * 1000)
        return None, "Empty message"
    if alert.get("severity") not in ["low", "medium", "high", "critical"]:
        record("validate", False, (time.time() - start) * 1000)
        return None, f"Bad severity: {alert.get('severity')}"
    record("validate", True, (time.time() - start) * 1000)
    return alert, None

def classify(alert):
    start = time.time()
    # Simulate transient failure (10% chance)
    if random.random() < 0.10:
        record("classify", False, (time.time() - start) * 1000)
        return None, "Model timeout (transient)"
    msg = alert["message"].lower()
    if any(w in msg for w in ["cpu", "slow", "query"]):
        cat = "performance"
    elif any(w in msg for w in ["disk", "space"]):
        cat = "storage"
    elif any(w in msg for w in ["replication", "lag"]):
        cat = "replication"
    else:
        cat = "other"
    alert["category"] = cat
    record("classify", True, (time.time() - start) * 1000)
    return alert, None

def store(alert):
    start = time.time()
    # Simulate storage (just collect results)
    alert["stored_at"] = datetime.now().isoformat()
    record("store", True, (time.time() - start) * 1000)
    return alert, None

# Process one alert through the full pipeline
def process_alert(raw):
    stages = [
        ("ingest", ingest),
        ("validate", validate),
        ("classify", classify),
        ("store", store),
    ]
    data = raw
    for stage_name, func in stages:
        result, error = func(data)
        if error:
            # Retry once for classify (transient failures)
            if stage_name == "classify":
                result, error = func(data)
                if not error:
                    data = result
                    continue
            # Send to DLQ
            dlq.append({"data": raw, "stage": stage_name, "error": error})
            return None
        data = result
    return data

# Generate test alerts
test_alerts = []
messages = [
    ("CPU at 95%", "critical"), ("Disk at 90%", "high"),
    ("Replication lag 60s", "high"), ("Slow query 45s", "medium"),
    ("SSL expiring", "low"), ("Connection pool full", "critical"),
    ("", "high"),                   # empty message - will fail validation
    ("WAL growing", "urgent"),      # bad severity - will fail validation
]

for i, (msg, sev) in enumerate(messages * 5):  # 40 total
    test_alerts.append({"id": i + 1, "message": msg, "severity": sev})

# Process all
stored = []
for alert in test_alerts:
    result = process_alert(alert)
    if result:
        stored.append(result)

# Report
print(f"Processed {len(test_alerts)} alerts")
print(f"Stored: {len(stored)}")
print(f"Failed (DLQ): {len(dlq)}")

print(f"\nMetrics per stage:")
print(f"{'Stage':>12s}  {'OK':>5s}  {'Fail':>5s}  {'Rate':>6s}")
print("-" * 35)
for stage in ["ingest", "validate", "classify", "store"]:
    s = metrics[stage]
    total = s["ok"] + s["fail"]
    rate = s["ok"] / total * 100 if total > 0 else 0
    print(f"{stage:>12s}  {s['ok']:>5d}  {s['fail']:>5d}  {rate:>5.1f}%")

print(f"\nDLQ breakdown:")
from collections import Counter
dlq_stages = Counter(d["stage"] for d in dlq)
for stage, count in dlq_stages.most_common():
    print(f"  {stage}: {count} failures")

print("\nThis is a production-ready pipeline pattern:")
print("  ingest -> validate -> classify -> store")
print("  + retries + DLQ + monitoring")
PYEOF
```

---

## What You Practiced

| Exercise | Skill | Production Use |
|----------|-------|---------------|
| Deduplication stage | Build custom stages | Prevent duplicate processing |
| Retry with jitter | Prevent thundering herd | Distributed system resilience |
| Fallback classification | Graceful degradation | Keep pipeline running when model fails |
| DLQ replay | Recover failed items | Fix bugs and reprocess |
| End-to-end pipeline | Combine all patterns | Production pipeline template |
