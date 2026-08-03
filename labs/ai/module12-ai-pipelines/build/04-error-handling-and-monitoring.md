# Build 04: Error Handling and Monitoring

Production pipelines fail. Networks timeout, models crash, data is malformed. This guide builds resilient pipelines that handle errors gracefully and alert you when something goes wrong.

---

## Step 1. Retry logic

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import time
import random

random.seed(42)

print("""
Retry Logic: Automatically retry failed operations.

Rules:
  1. Only retry TRANSIENT failures (timeout, rate limit, connection error)
  2. Don't retry PERMANENT failures (invalid data, wrong model, auth error)
  3. Use exponential backoff (wait longer between each retry)
  4. Set a maximum number of retries
""")

def retry_with_backoff(func, max_retries=3, base_delay=1.0):
    """Retry a function with exponential backoff."""
    for attempt in range(max_retries + 1):
        try:
            result = func()
            if attempt > 0:
                print(f"    Succeeded on attempt {attempt + 1}")
            return result
        except Exception as e:
            if attempt == max_retries:
                print(f"    Failed after {max_retries + 1} attempts: {e}")
                raise  # re-raise the exception after all retries exhausted
            # raise without arguments re-raises the current exception

            delay = base_delay * (2 ** attempt)
            # Exponential backoff: 1s, 2s, 4s, 8s...
            # 2 ** attempt: 2^0=1, 2^1=2, 2^2=4

            print(f"    Attempt {attempt + 1} failed: {e}. Retrying in {delay:.1f}s...")
            time.sleep(delay * 0.01)  # shortened for demo (real: time.sleep(delay))

# Simulate a flaky API (fails 60% of the time)
call_count = 0

def flaky_embedding_api():
    """Simulates an embedding API that sometimes fails."""
    # "global" lets a function modify a variable defined outside the function.
    # Without "global", Python would create a new local variable instead.
    # DBA analogy: like a session variable (SET myvar = ...) vs a local variable in PL/pgSQL.
    global call_count
    call_count += 1
    if random.random() < 0.6:
        raise ConnectionError("API timeout: embedding service unreachable")
    return [0.1, 0.2, 0.3]  # simulated embedding

print("Retry with Exponential Backoff:")
print("-" * 45)

for i in range(3):
    call_count = 0
    try:
        result = retry_with_backoff(flaky_embedding_api, max_retries=3)
        print(f"  Test {i+1}: Got embedding after {call_count} API call(s)")
    except ConnectionError:
        print(f"  Test {i+1}: Gave up after {call_count} API call(s)")

print()
print("Exponential backoff prevents overwhelming a struggling service")
print("1s -> 2s -> 4s gives the service time to recover")
PYEOF
```

---

## Step 2. Dead letter queue

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime

print("""
Dead Letter Queue (DLQ): Save failed items for later investigation.

When an item fails processing after all retries:
  1. Don't silently drop it
  2. Save it to a "dead letter" queue/table
  3. Include: the original data, the error message, timestamp
  4. Review and fix manually or reprocess later

DBA analogy: Like an error log table.
  INSERT INTO processing_errors (data, error, created_at)
  VALUES (failed_row, error_message, NOW());
""")

dlq_file = "/tmp/dead_letter_queue.jsonl"
# Clear previous
open(dlq_file, "w").close()

def send_to_dlq(item, error, stage):
    """Save a failed item to the dead letter queue."""
    dlq_entry = {
        "original_data": item,
        "error": str(error),
        "stage": stage,
        "timestamp": datetime.now().isoformat(),
        "retry_count": item.get("_retry_count", 0),
    }
    with open(dlq_file, "a") as f:
        f.write(json.dumps(dlq_entry) + "\n")
    return dlq_entry

# Process alerts with DLQ handling
alerts = [
    {"id": 1, "message": "CPU at 95%", "severity": "critical"},
    {"id": 2, "message": "", "severity": "high"},           # empty message -> fails validation
    {"id": 3, "message": "Disk full", "severity": "urgent"}, # invalid severity -> fails validation
    {"id": 4, "message": None, "severity": "low"},           # null message -> fails processing
    {"id": 5, "message": "Replication lag 60s", "severity": "high"},
]

processed = []
failed = []

print("Processing alerts with Dead Letter Queue:")
print("-" * 55)

for alert in alerts:
    try:
        # Validate
        if not alert.get("message"):
            raise ValueError("Empty or null message")
        if alert["severity"] not in ["low", "medium", "high", "critical"]:
            raise ValueError(f"Invalid severity: {alert['severity']}")

        # Process (classify)
        msg = alert["message"].lower()
        if "cpu" in msg:
            cat = "performance"
        elif "disk" in msg:
            cat = "storage"
        elif "replication" in msg or "lag" in msg:
            cat = "replication"
        else:
            cat = "unknown"

        alert["category"] = cat
        processed.append(alert)
        print(f"  [OK]  id={alert['id']}  {alert['message'][:30]}")

    except Exception as e:
        dlq_entry = send_to_dlq(alert, e, "processing")
        failed.append(dlq_entry)
        print(f"  [DLQ] id={alert['id']}  Error: {e}")

print(f"\nProcessed: {len(processed)}")
print(f"Sent to DLQ: {len(failed)}")

# Show DLQ contents
print(f"\nDead Letter Queue ({dlq_file}):")
with open(dlq_file) as f:
    for line in f:
        entry = json.loads(line)
        print(f"  Stage: {entry['stage']}, Error: {entry['error']}")
        print(f"  Data: {json.dumps(entry['original_data'])}")
        print()

print("DLQ items can be:")
print("  1. Fixed manually and reprocessed")
print("  2. Used to improve validation rules")
print("  3. Tracked for error rate monitoring")
PYEOF
```

---

## Step 3. Pipeline monitoring and logging

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import time
from datetime import datetime
from collections import defaultdict

class PipelineMonitor:
    """Track pipeline metrics."""

    def __init__(self, name):
        self.name = name
        self.metrics = defaultdict(lambda: {"success": 0, "failure": 0, "total_ms": 0})
        # defaultdict creates a new dict entry automatically when accessed
        # lambda: {...} is the factory function that creates the default value
        self.start_time = datetime.now()

    def record(self, stage, success, duration_ms):
        """Record a stage execution."""
        key = "success" if success else "failure"
        self.metrics[stage][key] += 1
        self.metrics[stage]["total_ms"] += duration_ms

    def report(self):
        """Print a monitoring report."""
        print(f"\nPipeline Monitoring Report: {self.name}")
        print(f"Report time: {datetime.now().isoformat()}")
        print(f"Running since: {self.start_time.isoformat()}")
        print("=" * 65)
        print(f"{'Stage':>15s}  {'Success':>8s}  {'Failure':>8s}  {'Rate':>6s}  {'Avg ms':>7s}")
        print("-" * 50)

        total_success = 0
        total_failure = 0

        for stage, stats in self.metrics.items():
            total = stats["success"] + stats["failure"]
            rate = stats["success"] / total * 100 if total > 0 else 0
            avg_ms = stats["total_ms"] / total if total > 0 else 0
            total_success += stats["success"]
            total_failure += stats["failure"]
            print(f"{stage:>15s}  {stats['success']:>8d}  {stats['failure']:>8d}  "
                  f"{rate:>5.1f}%  {avg_ms:>6.1f}")

        print("-" * 50)
        grand_total = total_success + total_failure
        overall_rate = total_success / grand_total * 100 if grand_total > 0 else 0
        print(f"{'TOTAL':>15s}  {total_success:>8d}  {total_failure:>8d}  {overall_rate:>5.1f}%")

        # Health check
        print()
        if overall_rate < 90:
            print("STATUS: DEGRADED - success rate below 90%")
        elif overall_rate < 95:
            print("STATUS: WARNING - success rate below 95%")
        else:
            print("STATUS: HEALTHY")

# Simulate a monitored pipeline run
monitor = PipelineMonitor("Alert Classification Pipeline")

import random
random.seed(42)

# Simulate 100 alerts through the pipeline
for i in range(100):
    # Ingest
    start = time.time()
    success = random.random() > 0.02  # 2% ingest failure rate
    duration = random.uniform(0.5, 2.0)
    monitor.record("ingest", success, duration)

    if not success:
        continue

    # Validate
    success = random.random() > 0.05  # 5% validation failure rate
    duration = random.uniform(0.1, 0.5)
    monitor.record("validate", success, duration)

    if not success:
        continue

    # Classify
    success = random.random() > 0.03  # 3% classification failure rate
    duration = random.uniform(1.0, 5.0)
    monitor.record("classify", success, duration)

    if not success:
        continue

    # Store
    success = random.random() > 0.01  # 1% storage failure rate
    duration = random.uniform(0.5, 3.0)
    monitor.record("store", success, duration)

monitor.report()

print("""
Production monitoring checklist:
  1. Track success/failure rate per stage
  2. Track average latency per stage
  3. Alert when success rate drops below 95%
  4. Alert when latency exceeds SLA
  5. Track DLQ size (growing = systemic problem)
  6. Daily report: total processed, error rate, top errors
""")
PYEOF
```

Expected output (yours will differ):

```
Pipeline Monitoring Report: Alert Classification Pipeline
Report time: 2024-01-15T10:30:00
============================================================
          Stage   Success   Failure    Rate   Avg ms
--------------------------------------------------
         ingest        98         2   98.0%     1.2
       validate        93         5   94.9%     0.3
       classify        90         3   96.8%     3.1
          store        89         1   98.9%     1.7
--------------------------------------------------
          TOTAL       370        11   97.1%

STATUS: HEALTHY
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Retry with backoff | Retry transient failures with increasing delay | Connection retry with pg_isready |
| Dead letter queue | Save failed items for investigation | Error log table |
| Pipeline monitor | Track success rate and latency per stage | pg_stat_statements for pipelines |
| Health check | Determine if pipeline is degraded | Nagios/Prometheus alerts |
| Logging | Record all events for debugging | PostgreSQL log files |
