# Survive 01: Launch Day Failure

You deploy dbaBrain to production. Within 10 minutes, the classifier starts returning errors for 30% of requests. The error rate spikes, the on-call DBA gets paged, and stakeholders are asking why the new AI system is failing.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'
from datetime import datetime, timedelta

print("""
SCENARIO: Launch Day Failure

Timeline:
  09:00  dbaBrain v1.0 deployed to production
  09:02  First alerts processed successfully (looking good!)
  09:05  Error rate starts climbing: 5%, 10%, 15%...
  09:08  On-call DBA paged: "dbaBrain error rate > 10%"
  09:10  Error rate at 30%. Stakeholders asking questions.
  09:12  Some alerts are returning wrong categories
  09:15  Engineering decides to investigate before rolling back
  09:20  Root cause found (see below)
  09:22  Fix applied, error rate drops to 0%
  09:30  Post-incident review scheduled

The 30% of failing requests all have something in common:
they include metric data with unexpected field names.
""")

print("Error Log (first 5 errors):")
print("=" * 55)

errors = [
    {
        "time": "09:05:12",
        "alert_text": "High memory usage on pg-analytics",
        "metrics": {"memory_percent": 92, "swap_used_mb": 4096},
        "error": "KeyError: 'cpu_percent' - metric not found in normalization ranges",
    },
    {
        "time": "09:05:14",
        "alert_text": "IO wait high on pg-primary-2",
        "metrics": {"iowait_percent": 45, "disk_read_mbps": 500},
        "error": "KeyError: 'iowait_percent' - metric not found in normalization ranges",
    },
    {
        "time": "09:05:18",
        "alert_text": "Lock contention on pg-oltp-1",
        "metrics": {"lock_count": 350, "blocked_queries": 12},
        "error": "KeyError: 'lock_count' - metric not found in normalization ranges",
    },
    {
        "time": "09:06:02",
        "alert_text": "Temp file usage spike",
        "metrics": {"temp_files_mb": 2048, "work_mem_used_percent": 95},
        "error": "KeyError: 'temp_files_mb' - metric not found in normalization ranges",
    },
    {
        "time": "09:06:15",
        "alert_text": "Autovacuum workers maxed out",
        "metrics": {"autovacuum_workers": 5, "dead_tuples_million": 8},
        "error": "KeyError: 'autovacuum_workers' - metric not found in normalization ranges",
    },
]

for e in errors:
    print(f"\n  [{e['time']}] {e['alert_text']}")
    print(f"    Metrics: {e['metrics']}")
    print(f"    Error: {e['error']}")

print(f"""
Impact:
  - 30% of alerts failing (the ones with non-standard metrics)
  - 70% still working (alerts with cpu_percent, disk_percent, etc.)
  - Zero P1 alerts missed (critical metric alerts use standard fields)
  - DBA trust in the system damaged on launch day
  - Stakeholder confidence shaken

The problem: the classifier only knows about 5 metric names.
Production sends 20+ different metric names.
The code crashes instead of handling unknown metrics gracefully.
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'
print("Investigation: Why 30% of Requests Failed")
print("=" * 55)

print("""
Root Cause: Brittle Metric Handling

The FeatureExtractor was built with a fixed list of known metrics:

  KNOWN_METRICS = {
      "cpu_percent": (0, 100),
      "disk_percent": (0, 100),
      "connections": (0, 500),
      "replication_lag_seconds": (0, 3600),
      "query_time_seconds": (0, 300),
  }

The BROKEN code tried to normalize ALL incoming metrics:

  def extract_metrics(self, metrics):
      normalized = {}
      for name, value in metrics.items():
          # BUG: crashes if metric name not in KNOWN_METRICS
          min_val, max_val = self.KNOWN_METRICS[name]  # KeyError!
          normalized[name] = (value - min_val) / (max_val - min_val)
      return normalized

Production monitoring systems send MANY metric names:
  - memory_percent, swap_used_mb (memory monitoring)
  - iowait_percent, disk_read_mbps (IO monitoring)
  - lock_count, blocked_queries (lock monitoring)
  - temp_files_mb, work_mem_used_percent (query monitoring)
  - autovacuum_workers, dead_tuples_million (maintenance monitoring)

The code assumed it knew ALL possible metric names.
It didn't. 30% of real alerts include metrics the code never saw.

Contributing factors:
  1. No input validation (didn't check if metric name is known)
  2. No graceful handling of unknown metrics (crash vs skip)
  3. Testing only used the 5 known metrics (didn't test unknown)
  4. No staging test with real production data
""")

# Show the broken code vs the fix
print("Broken Code:")
print("-" * 40)
print("""
  def extract_metrics(self, metrics):
      normalized = {}
      for name, value in metrics.items():
          min_val, max_val = self.KNOWN_METRICS[name]  # CRASHES!
          normalized[name] = (value - min_val) / (max_val - min_val)
      return normalized
""")

print("Fixed Code:")
print("-" * 40)
print("""
  def extract_metrics(self, metrics):
      normalized = {}
      for name, value in metrics.items():
          if name in self.KNOWN_METRICS:
              min_val, max_val = self.KNOWN_METRICS[name]
              normalized[name] = max(0.0, min(1.0,
                  (value - min_val) / (max_val - min_val)
              ))
          # else: skip unknown metrics (don't crash)
      return normalized
""")

print("""
The fix is ONE LINE: check if the metric name is known.
Unknown metrics are simply skipped.
The classifier still works using the metrics it does know.

DBA analogy: like pg_stat_statements encountering a new query.
It doesn't crash. It creates a new entry for that query.
Your code should handle unknown inputs gracefully.
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
print("""
FIX: Defensive Input Handling

Three layers of defense against unknown inputs:

Layer 1: Skip unknown metrics (don't crash)
Layer 2: Log unknown metrics (so you can add them later)
Layer 3: Validate inputs at the API boundary (before processing)
""")

print("Layer 1: Graceful Unknown Metric Handling")
print("=" * 50)

class RobustFeatureExtractor:
    """
    Feature extractor that handles unknown metrics gracefully.

    DBA analogy: like a PostgreSQL function with EXCEPTION handling.
    BEGIN ... EXCEPTION WHEN others THEN ... END;
    Don't let one bad input crash the whole function.
    """

    KNOWN_METRICS = {
        "cpu_percent": (0, 100),
        "disk_percent": (0, 100),
        "connections": (0, 500),
        "replication_lag_seconds": (0, 3600),
        "query_time_seconds": (0, 300),
    }

    KEYWORDS = {
        "performance": ["slow", "cpu", "timeout", "load", "latency"],
        "storage": ["disk", "space", "full", "tablespace"],
        "replication": ["replica", "lag", "standby", "wal"],
        "connectivity": ["connection", "refused", "pool", "max_connections"],
        "security": ["permission", "denied", "login", "auth"],
        "backup": ["backup", "archive", "pitr", "restore"],
    }

    def __init__(self):
        # Track unknown metrics for future improvement
        self.unknown_metrics_seen = {}

    def extract(self, text, metrics):
        """Extract features, gracefully handling unknown inputs."""

        # Text features (same as before - keywords are controlled by us)
        text_lower = text.lower()
        text_features = {}
        for category, keywords in self.KEYWORDS.items():
            text_features[category] = sum(
                1 for kw in keywords if kw in text_lower
            )

        # Metric features - FIXED: skip unknown metrics
        metric_features = {}
        for name, value in metrics.items():
            if name in self.KNOWN_METRICS:
                min_val, max_val = self.KNOWN_METRICS[name]
                # Normalize to 0-1 range with clipping
                normalized = max(0.0, min(1.0,
                    (value - min_val) / (max_val - min_val)
                ))
                metric_features[name] = normalized
            else:
                # Layer 2: Log unknown metrics (don't crash)
                self.unknown_metrics_seen[name] = \
                    self.unknown_metrics_seen.get(name, 0) + 1

        return text_features, metric_features

    def get_unknown_metrics_report(self):
        """Report which unknown metrics we've seen and how often."""
        return dict(sorted(
            self.unknown_metrics_seen.items(),
            key=lambda x: x[1],
            reverse=True
        ))


# Test with the alerts that caused the crash
extractor = RobustFeatureExtractor()

test_cases = [
    ("High memory usage on pg-analytics", {"memory_percent": 92, "swap_used_mb": 4096}),
    ("IO wait high on pg-primary-2", {"iowait_percent": 45, "disk_read_mbps": 500}),
    ("Lock contention on pg-oltp-1", {"lock_count": 350, "cpu_percent": 75}),
    ("Disk almost full", {"disk_percent": 94, "temp_files_mb": 2048}),
    ("CPU spike with slow queries", {"cpu_percent": 95, "query_time_seconds": 120}),
]

print("\nProcessing alerts that previously crashed:")
print("-" * 50)

for text, metrics in test_cases:
    text_features, metric_features = extractor.extract(text, metrics)
    known = list(metric_features.keys())
    unknown = [k for k in metrics if k not in extractor.KNOWN_METRICS]
    status = "OK" if True else "ERROR"  # no crash = OK

    print(f"\n  [{status}] {text}")
    print(f"    Input metrics:  {list(metrics.keys())}")
    print(f"    Known (used):   {known if known else '(none)'}")
    print(f"    Unknown (skip): {unknown if unknown else '(none)'}")


# Show unknown metrics report
print(f"\nUnknown Metrics Report:")
print(f"  (Use this to decide which metrics to add next)")
report = extractor.get_unknown_metrics_report()
for name, count in report.items():
    print(f"    {name:<30s} seen {count} time(s)")


print(f"""

Layer 3: Input Validation at API Boundary
  Before the alert even reaches the classifier,
  validate the input at the API level:

  class AlertInput:
      alert_text: str          # required, min 1 character
      metrics: dict            # optional, any key-value pairs
      environment: str         # must be: production, staging, or development

  Validation rules:
    - alert_text must be a non-empty string
    - metrics must be a dict (not a list, not a string)
    - metric values must be numbers (not strings, not None)
    - environment must be one of the allowed values

  If validation fails, return 400 Bad Request (don't process).
  If validation passes, the classifier handles unknown metrics gracefully.

Prevention checklist:
  1. Never assume you know all possible inputs
  2. Skip unknown data gracefully (log it, don't crash)
  3. Validate at the API boundary (reject garbage early)
  4. Test with REAL production data before launching
  5. Track unknown inputs to identify what to add next
  6. Have a rollback plan ready on launch day

DBA analogy:
  Layer 1 = EXCEPTION WHEN others THEN (handle errors in PL/pgSQL)
  Layer 2 = pg_stat_statements (track what queries you're seeing)
  Layer 3 = pg_hba.conf (reject bad connections before they reach the database)
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Unknown metric names crash the code | 30% of real alerts use metrics you didn't anticipate | Skip unknown metrics, don't crash |
| No input validation | Bad data reaches the classifier | Validate at the API boundary |
| Testing with fake data only | Didn't discover real production metric names | Test with real production data before launch |
| No unknown input tracking | Can't improve what you don't measure | Log unknown metrics for future improvement |
| No rollback plan | Launch day failure with no quick escape | Always have a one-click rollback ready |
