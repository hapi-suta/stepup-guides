# Survive 01: Silent Pipeline Stall

Your alert classification pipeline has been running for 3 weeks. No errors in the logs. But the operations team says they haven't received any classified alerts in 2 days. The pipeline appears healthy but is doing nothing.

---

## The Disaster

On your **Mac terminal**, run the injection script:

```bash
python3 << 'PYEOF'
import json
import time
from datetime import datetime, timedelta

print("""
SCENARIO: Silent Pipeline Stall

Your pipeline has 4 stages:
  ingest -> validate -> classify -> store

The pipeline reports "healthy" - no errors, no crashes.
But ZERO alerts have been classified in 48 hours.

Your job: find the root cause and fix it.
""")

# Simulate the stalled pipeline
queue_file = "/tmp/survive_stall_queue.jsonl"
results_file = "/tmp/survive_stall_results.jsonl"
metrics_file = "/tmp/survive_stall_metrics.json"

# The queue has been filling up for 2 days
alerts = []
for i in range(200):
    alerts.append({
        "id": i + 1,
        "message": f"Alert {i+1}: various database issue",
        "severity": "high",
        "source": "prometheus",
        "timestamp": (datetime.now() - timedelta(hours=48) + timedelta(minutes=i * 14)).isoformat(),
    })

with open(queue_file, "w") as f:
    for a in alerts:
        f.write(json.dumps(a) + "\n")

# Results file is empty (nothing processed in 2 days)
open(results_file, "w").close()

# Metrics show the problem (if you look carefully)
metrics = {
    "pipeline": "alert_classification",
    "status": "running",
    "last_check": datetime.now().isoformat(),
    "stages": {
        "ingest": {"success": 200, "failure": 0, "last_run": (datetime.now() - timedelta(hours=48)).isoformat()},
        "validate": {"success": 200, "failure": 0, "last_run": (datetime.now() - timedelta(hours=48)).isoformat()},
        "classify": {"success": 0, "failure": 0, "last_run": "never"},
        "store": {"success": 0, "failure": 0, "last_run": "never"},
    },
    "queue_depth": 200,
    "error_count": 0,
    "last_error": None,
}

with open(metrics_file, "w") as f:
    json.dump(metrics, f, indent=2)

print(f"Pipeline files created:")
print(f"  Queue:   {queue_file} ({len(alerts)} alerts waiting)")
print(f"  Results: {results_file} (empty)")
print(f"  Metrics: {metrics_file}")
print()
print("Step 1: Check the metrics file to understand what's happening")
print(f"  cat {metrics_file}")
PYEOF
```

---

## Investigate

On your **Mac terminal**, check the metrics:

```bash
python3 << 'PYEOF'
import json

# Load metrics
with open("/tmp/survive_stall_metrics.json") as f:
    metrics = json.load(f)

print("Pipeline Metrics:")
print("=" * 50)
print(f"Status: {metrics['status']}")
print(f"Queue depth: {metrics['queue_depth']}")
print(f"Total errors: {metrics['error_count']}")
print()

print("Stage breakdown:")
print(f"{'Stage':>12s}  {'Success':>8s}  {'Failure':>8s}  Last Run")
print("-" * 60)
for stage, stats in metrics["stages"].items():
    print(f"{stage:>12s}  {stats['success']:>8d}  {stats['failure']:>8d}  {stats['last_run']}")

print()
print("What do you notice?")
print("  - ingest and validate ran 48 hours ago (200 items each)")
print("  - classify has NEVER run (0 success, 0 failure)")
print("  - store has NEVER run")
print("  - Queue has 200 items sitting there")
print("  - Error count is 0")
print()
print("ROOT CAUSE: The classify stage never executed.")
print("No errors because the stage was never called - not that it succeeded.")
print()
print("This is the 'silent stall' pattern:")
print("  A stage silently stops running, no errors are raised,")
print("  and the pipeline reports 'healthy' because error_count == 0.")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
import json
import time
from datetime import datetime, timedelta
from collections import defaultdict

print("""
FIX: Add "liveness" checks - not just error checks.

Three monitoring improvements:
  1. Check that each stage has run recently (not just that it hasn't errored)
  2. Check queue depth over time (growing queue = stalled consumer)
  3. Check throughput (items processed per hour)

DBA analogy:
  - Not just "is replication connected?" but "is replication ADVANCING?"
  - SELECT pg_last_wal_replay_lsn() hasn't changed in 2 hours = stall
  - Error count 0 doesn't mean healthy if no work is being done
""")

class LivenessMonitor:
    """Monitor pipeline liveness, not just errors."""

    def __init__(self, max_idle_seconds=300):
        self.max_idle_seconds = max_idle_seconds
        # If a stage hasn't run in this many seconds, it's stalled
        self.stage_last_run = {}
        self.stage_counts = defaultdict(int)
        self.alerts = []

    def record_run(self, stage):
        """Record that a stage just ran."""
        self.stage_last_run[stage] = datetime.now()
        self.stage_counts[stage] += 1

    def check_liveness(self):
        """Check if all stages are alive (running recently)."""
        now = datetime.now()
        stalled = []

        for stage, last_run in self.stage_last_run.items():
            idle_seconds = (now - last_run).total_seconds()
            if idle_seconds > self.max_idle_seconds:
                stalled.append({
                    "stage": stage,
                    "idle_seconds": idle_seconds,
                    "last_run": last_run.isoformat(),
                })

        return stalled

    def check_queue_growth(self, current_depth, previous_depth):
        """Check if queue is growing (sign of stall)."""
        if current_depth > previous_depth * 1.5 and current_depth > 10:
            # Queue grew by 50% and has more than 10 items
            return {
                "alert": "Queue growing",
                "current": current_depth,
                "previous": previous_depth,
                "growth": f"{(current_depth / previous_depth - 1) * 100:.0f}%"
            }
        return None

    def check_throughput(self, stage, expected_per_hour):
        """Check if throughput meets expectations."""
        count = self.stage_counts.get(stage, 0)
        if count < expected_per_hour * 0.5:  # below 50% of expected
            return {
                "alert": f"Low throughput on {stage}",
                "actual": count,
                "expected": expected_per_hour,
            }
        return None

# Demo: simulate the fixed monitoring
monitor = LivenessMonitor(max_idle_seconds=300)

# Simulate: ingest and validate ran, classify didn't
monitor.record_run("ingest")
monitor.record_run("validate")
# classify never runs - this is the bug

# Manually set ingest/validate to 48 hours ago (simulating the stall)
monitor.stage_last_run["ingest"] = datetime.now() - timedelta(hours=48)
monitor.stage_last_run["validate"] = datetime.now() - timedelta(hours=48)

print("Liveness Check Results:")
print("=" * 50)

# Check 1: liveness
stalled = monitor.check_liveness()
if stalled:
    print("STALLED STAGES:")
    for s in stalled:
        hours = s["idle_seconds"] / 3600
        print(f"  {s['stage']}: idle for {hours:.1f} hours (last: {s['last_run']})")
else:
    print("All stages are live")

# Check 2: missing stages
expected_stages = {"ingest", "validate", "classify", "store"}
running_stages = set(monitor.stage_last_run.keys())
missing = expected_stages - running_stages
if missing:
    print(f"\nMISSING STAGES (never ran): {missing}")

# Check 3: queue growth
queue_alert = monitor.check_queue_growth(current_depth=200, previous_depth=20)
if queue_alert:
    print(f"\nQUEUE ALERT: {queue_alert['alert']}")
    print(f"  Depth: {queue_alert['previous']} -> {queue_alert['current']} ({queue_alert['growth']})")

print()
print("With liveness monitoring, this stall would be caught in 5 minutes,")
print("not discovered 48 hours later by the ops team.")

print("""
Prevention checklist:
  1. Monitor stage LIVENESS (last run time), not just errors
  2. Monitor QUEUE DEPTH over time (growing = stalled)
  3. Monitor THROUGHPUT per stage (items/hour)
  4. Alert if ANY stage hasn't run within its expected interval
  5. "No errors" does NOT mean "healthy" - check work is being done
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Silent stall | No errors but no work done | Liveness checks (last run time) |
| Growing queue | Consumers stopped but producers didn't | Queue depth monitoring |
| Missing stages | Stage never registered | Check expected vs actual stages |
| Zero throughput | Pipeline running but idle | Throughput metrics per stage |
| "Healthy" pipeline | Status based only on error count | Combine error + liveness + throughput |
