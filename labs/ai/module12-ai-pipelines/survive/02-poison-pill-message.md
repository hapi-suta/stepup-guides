# Survive 02: Poison Pill Message

A single malformed alert is crashing your entire pipeline. Every time the batch processor picks it up, the pipeline dies. It restarts, picks up the same message, dies again. An infinite crash loop.

---

## The Disaster

On your **Mac terminal**, run the injection script:

```bash
python3 << 'PYEOF'
import json
import time
from datetime import datetime

print("""
SCENARIO: Poison Pill Message

Your batch pipeline processes alerts from a JSONL queue file.
It reads all pending alerts, processes them, clears the queue.

But one alert has a deeply nested JSON structure that causes
the classifier to hit infinite recursion and crash.

The pipeline restarts, reads the SAME queue (not cleared because
processing didn't finish), hits the same poison message, crashes again.

This has been happening for 6 hours. 847 valid alerts are stuck
behind one bad message.
""")

queue_file = "/tmp/survive_poison_queue.jsonl"
crash_log = "/tmp/survive_poison_crashes.log"

# Build the queue: 847 valid alerts + 1 poison pill
alerts = []
for i in range(847):
    alerts.append({
        "id": i + 1,
        "message": f"Normal alert {i+1}: database metric threshold exceeded",
        "severity": "high",
        "source": "prometheus",
    })

# The poison pill - deeply nested structure that crashes the classifier
poison = {
    "id": 848,
    "message": {"nested": {"deeper": {"deepest": "this is not a string"}}},
    "severity": "critical",
    "source": "broken_integration",
}
# Insert poison pill in the middle so you can't just skip the last item
alerts.insert(423, poison)

with open(queue_file, "w") as f:
    for a in alerts:
        f.write(json.dumps(a) + "\n")

# Simulate crash log
with open(crash_log, "w") as f:
    for i in range(12):
        ts = (datetime.now()).isoformat()
        f.write(f"[{ts}] Pipeline crashed: AttributeError: 'dict' object has no attribute 'lower'\n")
        f.write(f"[{ts}]   File classify.py, line 34: msg = alert['message'].lower()\n")
        f.write(f"[{ts}]   Processing alert id=848\n")
        f.write(f"[{ts}] Restarting pipeline (attempt {i+1})...\n\n")

print(f"Queue file: {queue_file} ({len(alerts)} alerts, 1 poison)")
print(f"Crash log:  {crash_log} (12 restart attempts)")
print()
print("Step 1: Check the crash log")
print(f"  Look at {crash_log}")
PYEOF
```

---

## Investigate

On your **Mac terminal**, check the crash log:

```bash
python3 << 'PYEOF'
print("Crash Log (last 3 entries):")
print("=" * 60)

with open("/tmp/survive_poison_crashes.log") as f:
    lines = f.readlines()

# Show last 3 crash entries (12 lines)
for line in lines[-12:]:
    print(f"  {line.rstrip()}")

print()
print("Pattern: same alert (id=848) crashes the pipeline every time.")
print("The pipeline restarts but picks up the same message again.")
print()
print("This is a 'poison pill' - one bad message that blocks all processing.")
print()
print("Let's look at the poison message:")

import json
with open("/tmp/survive_poison_queue.jsonl") as f:
    for i, line in enumerate(f):
        alert = json.loads(line)
        if alert.get("id") == 848:
            print(f"\n  Line {i+1}: {json.dumps(alert, indent=2)}")
            print()
            print(f"  Problem: 'message' is a dict, not a string.")
            print(f"  alert['message'].lower() crashes because dicts don't have .lower()")
            break
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
import json
import time
from datetime import datetime

print("""
FIX: Three-layer defense against poison pills.

Layer 1: Input validation (catch bad data before processing)
Layer 2: Per-item error handling (isolate failures to single items)
Layer 3: Poison pill detection (auto-quarantine repeat offenders)

DBA analogy:
  Layer 1: CHECK constraints reject bad data on INSERT
  Layer 2: ON CONFLICT DO NOTHING - one bad row doesn't abort the batch
  Layer 3: pg_stat_activity kill queries that keep crashing
""")

queue_file = "/tmp/survive_poison_queue.jsonl"
dlq_file = "/tmp/survive_poison_dlq.jsonl"
results_file = "/tmp/survive_poison_results.jsonl"

# Clear outputs
open(dlq_file, "w").close()
open(results_file, "w").close()

# Layer 1: Input validation
def validate_alert(alert):
    """Validate alert structure before processing."""
    # Check message is a string
    if not isinstance(alert.get("message"), str):
        return False, f"'message' must be a string, got {type(alert.get('message')).__name__}"

    # Check message is not empty
    if not alert["message"].strip():
        return False, "Empty message"

    # Check severity is valid
    if alert.get("severity") not in ["low", "medium", "high", "critical"]:
        return False, f"Invalid severity: {alert.get('severity')}"

    return True, None

# Layer 2: Per-item processing with isolation
def process_alert_safe(alert):
    """Process a single alert with error isolation."""
    try:
        # Validate first
        valid, error = validate_alert(alert)
        if not valid:
            return None, error

        # Classify
        msg = alert["message"].lower()
        if any(w in msg for w in ["cpu", "slow", "query"]):
            cat = "performance"
        elif any(w in msg for w in ["disk", "space"]):
            cat = "storage"
        elif any(w in msg for w in ["replication", "lag"]):
            cat = "replication"
        else:
            cat = "other"

        return {**alert, "category": cat}, None

    except Exception as e:
        # Layer 2: catch ANY unexpected error for this single item
        return None, f"Unexpected: {e}"

# Layer 3: Poison pill tracking
poison_tracker = {}  # id -> failure count

def is_poison_pill(alert_id, max_failures=2):
    """Check if an alert has failed too many times."""
    return poison_tracker.get(alert_id, 0) >= max_failures

def record_failure(alert_id):
    """Track failures per alert ID."""
    poison_tracker[alert_id] = poison_tracker.get(alert_id, 0) + 1

# Process the queue with all three layers
print("Processing queue with poison pill protection:")
print("=" * 55)

processed = 0
quarantined = 0
failed = 0

with open(queue_file) as f:
    alerts = [json.loads(line) for line in f if line.strip()]

print(f"Queue: {len(alerts)} alerts\n")

results = []
dlq_entries = []

for alert in alerts:
    alert_id = alert.get("id", "unknown")

    # Layer 3: skip known poison pills
    if is_poison_pill(alert_id):
        quarantined += 1
        continue

    # Layer 2: process with isolation
    result, error = process_alert_safe(alert)

    if result:
        results.append(result)
        processed += 1
    else:
        record_failure(alert_id)
        failed += 1
        dlq_entries.append({
            "alert": alert,
            "error": error,
            "failure_count": poison_tracker.get(alert_id, 0),
            "timestamp": datetime.now().isoformat(),
        })

# Save results
with open(results_file, "w") as f:
    for r in results:
        f.write(json.dumps(r) + "\n")

with open(dlq_file, "w") as f:
    for d in dlq_entries:
        f.write(json.dumps(d) + "\n")

# Clear the queue (all items handled)
open(queue_file, "w").close()

print(f"Results:")
print(f"  Processed:    {processed}")
print(f"  Failed (DLQ): {failed}")
print(f"  Quarantined:  {quarantined}")
print(f"  Queue:        cleared")

print(f"\nThe poison pill (id=848) went to DLQ. All 847 valid alerts processed.")
print(f"Pipeline didn't crash. No restart loop.")

# Show the poison pill in DLQ
print(f"\nDLQ contents ({dlq_file}):")
with open(dlq_file) as f:
    for line in f:
        entry = json.loads(line)
        alert_id = entry["alert"].get("id", "?")
        print(f"  id={alert_id}: {entry['error']}")

print("""
Prevention checklist:
  1. VALIDATE inputs before processing (type checks, not just null checks)
  2. ISOLATE failures - one bad item must not crash the batch
  3. TRACK repeat failures - auto-quarantine poison pills
  4. CLEAR the queue progressively (mark items done, don't wait for full batch)
  5. TEST with malformed data: wrong types, nested objects, huge payloads

  DBA parallel:
    - CHECK constraints = input validation
    - SAVEPOINT per row = error isolation
    - pg_stat_activity monitoring = poison pill detection
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Poison pill | One bad message blocks all processing | Input validation + per-item isolation |
| Crash loop | Pipeline restarts and hits same bad message | Quarantine repeat failures |
| Batch all-or-nothing | Entire batch fails if one item fails | Process and commit items individually |
| No type checking | Assumes message is always a string | isinstance() checks before processing |
| No failure tracking | Same item fails forever | Count failures per item, quarantine at threshold |
