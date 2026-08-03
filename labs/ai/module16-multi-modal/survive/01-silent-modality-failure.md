# Survive 01: Silent Modality Failure

Your multi-modal classifier has been running for months. Last week, the metrics pipeline broke - it's sending stale data (always the same values from 3 days ago). The text pipeline still works, but the fusion model trusts the (now-wrong) metrics and misclassifies 40% of alerts.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime, timedelta

print("""
SCENARIO: Silent Modality Failure

Your multi-modal pipeline:
  1. Text pipeline: reads alert messages (working fine)
  2. Metric pipeline: reads Prometheus metrics (BROKEN)
  3. Fusion model: combines both (trusting stale metrics)

What happened:
  Monday:    Prometheus exporter crashes on the metrics server
  Monday:    Metric pipeline starts returning cached data from Monday morning
  Tuesday:   Model keeps using Monday's metrics for ALL predictions
  Wednesday: On-call notices 40% of alerts are miscategorized
  Thursday:  Root cause found - metrics have been stale for 3 days

The problem is SILENT:
  - No errors in the log (cache returns valid-looking data)
  - No monitoring alert (metric values are in range, just old)
  - Model confidence is still high (it trusts the stale metrics)
  - Only noticed when humans checked the classifications manually
""")

# Show the impact
print("Impact: Misclassification Examples")
print("=" * 55)

# Stale metrics from Monday morning (everything was fine)
stale_metrics = {
    "cpu_percent": 35,
    "disk_percent": 42,
    "memory_percent": 55,
    "connections": 120,
    "replication_lag_seconds": 2,
    "last_updated": "2025-06-02T08:00:00",  # 3 days ago!
}

# Real alerts from Thursday (actual problems happening)
real_alerts = [
    {
        "text": "CPU at 98% - runaway queries",
        "actual_metrics": {"cpu_percent": 98},
        "actual_category": "performance",
    },
    {
        "text": "Disk 95% full on /pgdata",
        "actual_metrics": {"disk_percent": 95},
        "actual_category": "storage",
    },
    {
        "text": "Replication lag 300 seconds",
        "actual_metrics": {"replication_lag_seconds": 300},
        "actual_category": "replication",
    },
]

# What the model sees (stale metrics)
for alert in real_alerts:
    print(f"\n  Alert: '{alert['text']}'")
    print(f"    Actual metrics:  cpu={alert['actual_metrics'].get('cpu_percent', 'n/a')}%, "
          f"disk={alert['actual_metrics'].get('disk_percent', 'n/a')}%")
    print(f"    Stale metrics:   cpu={stale_metrics['cpu_percent']}%, "
          f"disk={stale_metrics['disk_percent']}%")
    print(f"    Text says:       {alert['actual_category']}")
    print(f"    Stale metric says: everything is normal (values from 3 days ago)")
    print(f"    Model decision:  WRONG (trusts metrics over text)")

print(f"""
ROOT CAUSE:
  The metric pipeline cached its last successful read.
  When Prometheus went down, it kept returning the cache.
  The cache had no expiration.
  The fusion model had no freshness check.

  DBA parallel: like a monitoring dashboard showing yesterday's
  data because the connection to the database dropped.
  Everything looks green, but it's a LIE.
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'
from datetime import datetime, timedelta

print("Investigation: Finding the Stale Data")
print("=" * 55)

# Simulate metric pipeline with caching
class BrokenMetricPipeline:
    """The broken pipeline that caused the incident."""

    def __init__(self):
        self.cache = None
        self.cache_time = None

    def fetch_metrics(self):
        """
        This is the broken code.
        It caches the result but NEVER checks if the cache is stale.
        """
        try:
            # This would normally call Prometheus API
            # But Prometheus is down, so it throws an exception
            raise ConnectionError("Prometheus unreachable")
        except Exception:
            # BUG: silently returns cached data, no matter how old
            if self.cache is not None:
                return self.cache        # could be days old!
            return {}

# Demonstrate the bug
pipeline = BrokenMetricPipeline()

# Monday morning: successful fetch
pipeline.cache = {"cpu_percent": 35, "disk_percent": 42}
pipeline.cache_time = datetime.now() - timedelta(days=3)

# Thursday: Prometheus is down, cache returns stale data
result = pipeline.fetch_metrics()
print(f"\n  Fetched metrics: {result}")
print(f"  Cache age: 3 days old!")
print(f"  Any error raised? No - it silently returned stale data")

# Detection methods
print(f"\nDetection Methods:")
print("-" * 55)

print("""
Method 1: Metric Freshness Check
  Every metric should have a timestamp.
  If timestamp > 5 minutes old, treat metrics as MISSING.

Method 2: Metric Variance Check
  Real metrics CHANGE over time.
  If cpu_percent is exactly 35.0 for 3 days, it's stale.
  Check: has the value changed in the last N readings?

Method 3: Metric Pipeline Health Check
  Separate from the data, check if the pipeline itself is alive.
  Heartbeat: "metric pipeline last successful fetch = X seconds ago"

Method 4: Cross-Modal Consistency Monitoring
  If text says "CPU at 98%" but metrics say cpu=35%,
  flag the contradiction and alert on high contradiction rate.
""")

# Show detection in action
print("Detection Method 1: Freshness Check")
print("-" * 40)

def check_freshness(metrics, max_age_seconds=300):
    """
    Check if metrics are fresh enough to use.
    Returns (is_fresh, age_seconds).
    """
    last_updated = metrics.get("last_updated")
    if last_updated is None:
        return False, float('inf')     # no timestamp = can't verify

    update_time = datetime.fromisoformat(last_updated)
    age = (datetime.now() - update_time).total_seconds()

    return age <= max_age_seconds, age

stale = {"cpu_percent": 35, "last_updated": (datetime.now() - timedelta(days=3)).isoformat()}
fresh = {"cpu_percent": 95, "last_updated": (datetime.now() - timedelta(seconds=30)).isoformat()}

is_fresh, age = check_freshness(stale)
print(f"  Stale metrics: fresh={is_fresh}, age={age/3600:.1f} hours")

is_fresh, age = check_freshness(fresh)
print(f"  Fresh metrics: fresh={is_fresh}, age={age:.0f} seconds")

print("""
  With freshness check: stale metrics would be rejected.
  The model would fall back to text-only mode (less accurate but not WRONG).
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
from datetime import datetime, timedelta

print("""
FIX: Four layers of protection against stale data.

Layer 1: Metric freshness check (reject old data)
Layer 2: Metric variance check (detect frozen values)
Layer 3: Pipeline health monitoring (detect upstream failures)
Layer 4: Cross-modal consistency alerts (detect contradictions)
""")

# Layer 1: Metric freshness
print("Layer 1: Metric Freshness Check")
print("=" * 50)

class FreshnessGuard:
    """
    Reject metrics that are too old.

    DBA analogy: like checking pg_stat_replication.replay_lag.
    If replay_lag > threshold, the standby data is stale.
    Don't route queries to a stale standby.
    """

    def __init__(self, max_age_seconds=300):
        self.max_age_seconds = max_age_seconds

    def check(self, metrics):
        """Returns (is_fresh, metrics_or_none, reason)."""
        last_updated = metrics.get("last_updated")
        if last_updated is None:
            return False, None, "no_timestamp"

        age = (datetime.now() - datetime.fromisoformat(last_updated)).total_seconds()

        if age > self.max_age_seconds:
            return False, None, f"stale_{age:.0f}s"

        return True, metrics, "fresh"

guard = FreshnessGuard(max_age_seconds=300)

test_metrics = [
    {"cpu_percent": 95, "last_updated": (datetime.now() - timedelta(seconds=30)).isoformat()},
    {"cpu_percent": 35, "last_updated": (datetime.now() - timedelta(hours=1)).isoformat()},
    {"cpu_percent": 35, "last_updated": (datetime.now() - timedelta(days=3)).isoformat()},
    {"cpu_percent": 50},  # no timestamp
]

for m in test_metrics:
    fresh, clean_m, reason = guard.check(m)
    age_str = m.get("last_updated", "none")[-8:] if "last_updated" in m else "no timestamp"
    status = "FRESH" if fresh else "STALE"
    print(f"  [{status:>5s}] cpu={m['cpu_percent']}% updated={age_str} reason={reason}")


# Layer 2: Variance check
print(f"\nLayer 2: Metric Variance Check")
print("=" * 50)

class VarianceGuard:
    """
    Detect frozen metrics (same value repeated).

    If cpu_percent is exactly 35.0 for the last 10 readings,
    it's probably stale/cached, not a real measurement.

    DBA analogy: if pg_stat_activity.query_start hasn't changed
    in an hour, the connection is probably idle/stuck.
    """

    def __init__(self, window_size=5, min_variance=0.01):
        self.window_size = window_size   # how many readings to check
        self.min_variance = min_variance # minimum acceptable variance
        self.history = {}                # metric_name -> [recent_values]

    def check(self, metrics):
        """Check if any metric appears frozen."""
        frozen_metrics = []

        for name, value in metrics.items():
            if name == "last_updated":
                continue

            # Add to history
            if name not in self.history:
                self.history[name] = []
            self.history[name].append(value)

            # Keep only recent values
            if len(self.history[name]) > self.window_size:
                self.history[name] = self.history[name][-self.window_size:]

            # Check variance
            values = self.history[name]
            if len(values) >= self.window_size:
                mean = sum(values) / len(values)
                variance = sum((v - mean) ** 2 for v in values) / len(values)

                if variance < self.min_variance:
                    frozen_metrics.append(name)

        return len(frozen_metrics) == 0, frozen_metrics

var_guard = VarianceGuard(window_size=5, min_variance=0.1)

# Simulate 5 readings of stale metrics (all the same)
print("\n  Simulating 5 identical metric readings:")
for i in range(5):
    m = {"cpu_percent": 35.0, "disk_percent": 42.0}
    is_varied, frozen = var_guard.check(m)
    status = "OK" if is_varied else f"FROZEN: {frozen}"
    print(f"    Reading {i+1}: cpu=35.0, disk=42.0 -> {status}")

# Simulate 5 readings of real metrics (they vary)
var_guard2 = VarianceGuard(window_size=5, min_variance=0.1)
print("\n  Simulating 5 varying metric readings:")
import random
random.seed(42)
for i in range(5):
    m = {"cpu_percent": 50 + random.uniform(-10, 10), "disk_percent": 80 + random.uniform(-2, 2)}
    is_varied, frozen = var_guard2.check(m)
    status = "OK" if is_varied else f"FROZEN: {frozen}"
    print(f"    Reading {i+1}: cpu={m['cpu_percent']:.1f}, disk={m['disk_percent']:.1f} -> {status}")


# Layer 3: Pipeline health
print(f"\nLayer 3: Pipeline Health Monitoring")
print("=" * 50)

class PipelineHealthMonitor:
    """
    Monitor the health of the metric pipeline itself.

    DBA analogy: like monitoring the monitoring.
    Your standby is replicating, but is your monitoring of
    the standby actually working? Meta-monitoring.
    """

    def __init__(self, max_no_fetch_seconds=120):
        self.last_successful_fetch = None
        self.consecutive_failures = 0
        self.max_no_fetch = max_no_fetch_seconds

    def record_success(self):
        self.last_successful_fetch = datetime.now()
        self.consecutive_failures = 0

    def record_failure(self):
        self.consecutive_failures += 1

    def is_healthy(self):
        if self.last_successful_fetch is None:
            return False, "never_fetched"

        age = (datetime.now() - self.last_successful_fetch).total_seconds()

        if self.consecutive_failures >= 3:
            return False, f"consecutive_failures={self.consecutive_failures}"

        if age > self.max_no_fetch:
            return False, f"last_fetch_{age:.0f}s_ago"

        return True, "healthy"

monitor = PipelineHealthMonitor()

# Simulate: 2 successes, then 5 failures
monitor.record_success()
print(f"  After 1 success: {monitor.is_healthy()}")
monitor.record_success()
print(f"  After 2 successes: {monitor.is_healthy()}")
for i in range(5):
    monitor.record_failure()
    healthy, reason = monitor.is_healthy()
    print(f"  After failure {i+1}: healthy={healthy}, reason={reason}")

print(f"""
Layer 4: Cross-Modal Consistency Alerts
  (Covered in USE Exercise 4 - Contradiction Detection)
  Track contradiction rate over time.
  Normal: <5% of predictions have contradictions.
  Alert threshold: >15% contradictions = investigate.

Prevention checklist:
  1. Every metric MUST have a timestamp (last_updated field)
  2. Reject metrics older than 5 minutes (freshness guard)
  3. Detect frozen values (variance guard)
  4. Monitor pipeline health (heartbeat)
  5. Track contradiction rate (cross-modal check)
  6. Graceful degradation: if metrics are stale, use text-only mode
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Stale cached metrics | Model trusts wrong data silently | Freshness check with timestamps |
| Frozen values | Same number repeated = not real data | Variance monitoring |
| Silent pipeline failure | No error, just stale cache | Pipeline health monitoring |
| No graceful degradation | Bad data worse than no data | Fall back to text-only mode |
| No cross-modal check | Contradictions go unnoticed | Track contradiction rate |
