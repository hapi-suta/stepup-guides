# Survive 02: Model Drift in Production

Three months after launch, dbaBrain's accuracy has silently dropped from 92% to 71%. No one noticed because overall request metrics (latency, error rate) look fine. The accuracy degradation happened gradually - 1-2% per week - and only shows up when you compare DBA corrections over time.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'
print("""
SCENARIO: Silent Model Drift

Your AI product has been running in production for 3 months.
Everything LOOKS healthy:
  - API latency: 18ms p95 (target: < 200ms)  CHECK
  - Error rate: 0.1% (target: < 1%)           CHECK
  - Uptime: 99.97% (target: 99.9%)            CHECK

But accuracy has been silently degrading:
  Week 1:  92% overall accuracy
  Week 4:  89% accuracy (still above 90% target? barely)
  Week 8:  82% accuracy (below target, no alert fired)
  Week 12: 71% accuracy (DBAs stop trusting the system)

What happened? The production data CHANGED, but the model didn't.
""")

print("Accuracy Over 12 Weeks:")
print("=" * 55)

# Simulate weekly accuracy data
weekly_data = [
    {"week": 1,  "accuracy": 0.92, "performance": 0.95, "storage": 0.93, "replication": 0.88, "connectivity": 0.90, "security": 0.91, "backup": 0.94},
    {"week": 2,  "accuracy": 0.91, "performance": 0.94, "storage": 0.92, "replication": 0.87, "connectivity": 0.89, "security": 0.90, "backup": 0.93},
    {"week": 3,  "accuracy": 0.91, "performance": 0.93, "storage": 0.91, "replication": 0.85, "connectivity": 0.88, "security": 0.91, "backup": 0.94},
    {"week": 4,  "accuracy": 0.89, "performance": 0.92, "storage": 0.90, "replication": 0.82, "connectivity": 0.85, "security": 0.89, "backup": 0.93},
    {"week": 5,  "accuracy": 0.87, "performance": 0.91, "storage": 0.89, "replication": 0.78, "connectivity": 0.82, "security": 0.88, "backup": 0.92},
    {"week": 6,  "accuracy": 0.85, "performance": 0.90, "storage": 0.88, "replication": 0.75, "connectivity": 0.79, "security": 0.87, "backup": 0.91},
    {"week": 7,  "accuracy": 0.83, "performance": 0.89, "storage": 0.86, "replication": 0.72, "connectivity": 0.76, "security": 0.86, "backup": 0.91},
    {"week": 8,  "accuracy": 0.82, "performance": 0.88, "storage": 0.85, "replication": 0.70, "connectivity": 0.74, "security": 0.85, "backup": 0.90},
    {"week": 9,  "accuracy": 0.79, "performance": 0.86, "storage": 0.83, "replication": 0.66, "connectivity": 0.71, "security": 0.84, "backup": 0.89},
    {"week": 10, "accuracy": 0.76, "performance": 0.84, "storage": 0.81, "replication": 0.62, "connectivity": 0.67, "security": 0.82, "backup": 0.88},
    {"week": 11, "accuracy": 0.74, "performance": 0.82, "storage": 0.80, "replication": 0.58, "connectivity": 0.63, "security": 0.81, "backup": 0.87},
    {"week": 12, "accuracy": 0.71, "performance": 0.80, "storage": 0.78, "replication": 0.54, "connectivity": 0.59, "security": 0.80, "backup": 0.86},
]

print(f"\n  {'Week':>4s}  {'Overall':>8s}  {'Perf':>6s}  {'Store':>6s}  {'Repl':>6s}  {'Conn':>6s}  {'Sec':>6s}  {'Back':>6s}")
print(f"  {'----':>4s}  {'--------':>8s}  {'------':>6s}  {'------':>6s}  {'------':>6s}  {'------':>6s}  {'------':>6s}  {'------':>6s}")

for w in weekly_data:
    bar = "#" * int(w["accuracy"] * 20)
    flag = ""
    if w["accuracy"] < 0.80:
        flag = " <-- BELOW THRESHOLD"
    print(f"  {w['week']:>4d}  {w['accuracy']:>7.0%}  {w['performance']:>5.0%}  {w['storage']:>5.0%}  {w['replication']:>5.0%}  {w['connectivity']:>5.0%}  {w['security']:>5.0%}  {w['backup']:>5.0%}{flag}")

print(f"""
Pattern:
  - Replication accuracy dropped fastest (88% -> 54%)
  - Connectivity accuracy dropped second (90% -> 59%)
  - Performance, storage, security, backup held up better

Why? The infrastructure team deployed Patroni (HA cluster manager)
in week 3. Patroni changed the alert text patterns:
  Before: "Replication lag on standby pg-standby-1"
  After:  "Patroni: node pg-standby-1 timeline diverged, needs rewind"

The keyword "replication" no longer appears in many replication alerts.
The classifier doesn't know words like "patroni", "timeline", "rewind".

Similarly, pgBouncer was upgraded in week 5:
  Before: "Connection pool exhausted, max_connections reached"
  After:  "pgbouncer: server connection limit reached for database app_db"

New vocabulary, same problems. The model is stuck in the past.
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'
print("Investigation: Why Accuracy Drifted")
print("=" * 55)

print("""
Root Cause: Data Drift (Production Data Changed, Model Didn't)

Three types of drift happened simultaneously:

1. VOCABULARY DRIFT (text patterns changed)
   - Patroni introduced new terms: "timeline", "rewind", "switchover"
   - pgBouncer upgrade changed error messages
   - New monitoring tools added different alert formats

2. METRIC DRIFT (new metrics appeared)
   - Patroni sends: "patroni_lag_bytes" instead of "replication_lag_seconds"
   - pgBouncer sends: "pool_waiting" instead of "connections"
   - New metrics the model never saw during training

3. DISTRIBUTION DRIFT (alert mix changed)
   - Before Patroni: 15% replication alerts
   - After Patroni: 25% replication alerts (more granular monitoring)
   - Categories the model was weakest at became more common

Why nobody noticed:
  1. No accuracy monitoring (only latency and error rate were tracked)
  2. No per-category accuracy tracking
  3. No drift detection (comparing current data to training data)
  4. DBA feedback was collected but not analyzed automatically
  5. The degradation was gradual (1-2% per week)

DBA analogy: like a slow memory leak.
  Week 1: 2 GB free
  Week 8: 500 MB free
  Week 12: OOM kill
  If you only monitor "is PostgreSQL running?", you miss the leak.
  You need to monitor the TREND, not just the current state.
""")

# Show the vocabulary differences
print("Vocabulary Comparison:")
print("-" * 50)

changes = [
    {
        "category": "replication",
        "old_terms": ["replication lag", "standby", "wal receiver", "streaming replication"],
        "new_terms": ["patroni", "timeline diverged", "needs rewind", "switchover", "dcs lost"],
        "model_knows": ["replica", "lag", "standby", "wal", "replication"],
    },
    {
        "category": "connectivity",
        "old_terms": ["connection refused", "max_connections", "connection pool exhausted"],
        "new_terms": ["pgbouncer server limit", "pool_waiting", "client_active exceeded", "reserve pool"],
        "model_knows": ["connection", "refused", "pool", "max_connections"],
    },
]

for change in changes:
    print(f"\n  Category: {change['category']}")
    print(f"    Model knows:     {change['model_knows']}")
    print(f"    Old alert terms: {change['old_terms'][:3]}")
    print(f"    New alert terms: {change['new_terms'][:3]}")

    # Check overlap
    model_set = set(" ".join(change["model_knows"]).lower().split())
    new_set = set(" ".join(change["new_terms"]).lower().split())
    overlap = model_set & new_set
    print(f"    Overlap: {overlap if overlap else 'NONE - model blind to new terms'}")

PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
from datetime import datetime

print("""
FIX: Detect and respond to model drift automatically.

Layer 1: Drift detection (catch it early)
Layer 2: Automatic accuracy monitoring (track per-category trends)
Layer 3: Keyword refresh process (update the model)
Layer 4: Retraining pipeline (systematic improvement)
""")

print("Layer 1: Drift Detection")
print("=" * 50)

class DriftDetector:
    """
    Detect when production data diverges from training data.

    Two types of drift:
      1. Vocabulary drift: new words appearing in alerts
      2. Accuracy drift: predictions getting worse over time

    DBA analogy: like monitoring for bloat.
    Table size growing faster than data = bloat = need VACUUM.
    Unknown words growing faster than known = drift = need retrain.
    """

    def __init__(self, known_keywords):
        # known_keywords: the keywords the model was trained on
        self.known_keywords = set()
        for category_keywords in known_keywords.values():
            self.known_keywords.update(kw.lower() for kw in category_keywords)

        # Track unknown words seen in production
        self.unknown_words = {}
        self.total_alerts = 0
        self.alerts_with_unknown = 0

    def check_text(self, alert_text):
        """
        Check if an alert contains words the model doesn't know.

        Returns the unknown words found.
        """
        self.total_alerts += 1
        words = set(alert_text.lower().split())
        unknown = words - self.known_keywords

        # Filter out common non-meaningful words
        stop_words = {"the", "a", "is", "on", "in", "to", "for", "of",
                      "and", "or", "not", "at", "by", "from", "with"}
        unknown = unknown - stop_words

        if unknown:
            self.alerts_with_unknown += 1
            for word in unknown:
                self.unknown_words[word] = self.unknown_words.get(word, 0) + 1

        return unknown

    def get_drift_score(self):
        """
        Calculate how much the data has drifted.

        Score 0.0 = no drift (all words known)
        Score 1.0 = complete drift (all words unknown)

        Alert thresholds:
          < 0.3: normal (some unknown words expected)
          0.3 - 0.5: moderate drift (consider updating keywords)
          > 0.5: severe drift (retrain urgently)
        """
        if self.total_alerts == 0:
            return 0.0
        return round(self.alerts_with_unknown / self.total_alerts, 3)

    def get_top_unknown_words(self, n=10):
        """Get the most frequent unknown words (candidates for new keywords)."""
        return sorted(
            self.unknown_words.items(),
            key=lambda x: x[1],
            reverse=True
        )[:n]


# Test drift detection with old and new alert styles
KNOWN_KEYWORDS = {
    "performance": ["slow", "cpu", "timeout", "load", "latency"],
    "storage": ["disk", "space", "full", "tablespace"],
    "replication": ["replica", "lag", "standby", "wal", "replication"],
    "connectivity": ["connection", "refused", "pool", "max_connections"],
    "security": ["permission", "denied", "login", "auth"],
    "backup": ["backup", "archive", "pitr", "restore"],
}

detector = DriftDetector(KNOWN_KEYWORDS)

# Old-style alerts (model knows these)
old_alerts = [
    "Replication lag on standby pg-standby-1",
    "High CPU usage causing slow queries",
    "Disk space full on tablespace pg_default",
    "Connection pool exhausted, max_connections reached",
]

# New-style alerts (model doesn't know these terms)
new_alerts = [
    "Patroni: node pg-standby-1 timeline diverged, needs rewind",
    "pgbouncer: server connection limit reached for database app_db",
    "Patroni: DCS lost, demoting primary to replica",
    "pgbouncer: reserve pool activated, client_active exceeded",
    "Citus: shard rebalancer stuck on node worker-3",
    "Patroni: switchover initiated by DBA, new leader elected",
]

print("\nOld-style alerts (known vocabulary):")
for alert in old_alerts:
    unknown = detector.check_text(alert)
    known_pct = 1.0 - (len(unknown) / max(1, len(alert.split())))
    print(f"  [{known_pct:.0%} known] {alert[:50]}")

print(f"\n  Drift score after old alerts: {detector.get_drift_score()}")

print("\nNew-style alerts (unknown vocabulary):")
for alert in new_alerts:
    unknown = detector.check_text(alert)
    if unknown:
        print(f"  Unknown words: {unknown}")
    print(f"    {alert[:50]}")

drift = detector.get_drift_score()
print(f"\n  Drift score after all alerts: {drift}")
if drift > 0.5:
    print(f"  SEVERE DRIFT - retrain urgently!")
elif drift > 0.3:
    print(f"  MODERATE DRIFT - update keywords soon")
else:
    print(f"  NORMAL - some unknown words expected")

print(f"\n  Top unknown words (add to keywords?):")
for word, count in detector.get_top_unknown_words(8):
    print(f"    '{word}' seen {count} time(s)")


print(f"""

Layer 2: Accuracy Trend Monitoring
{'=' * 50}""")

class AccuracyTrendMonitor:
    """
    Monitor accuracy trends and alert on degradation.

    Instead of just checking "is accuracy above 90%?",
    check "is accuracy TRENDING downward?"

    A 2% drop in one week might not trigger a threshold alert.
    But 2% drop every week for 6 weeks is a clear trend.

    DBA analogy: like monitoring disk usage RATE.
    85% disk isn't urgent. But 85% AND growing 2% per day?
    You'll be at 100% in a week. The TREND matters.
    """

    def __init__(self):
        self.weekly_accuracy = []

    def record_week(self, accuracy, per_category=None):
        self.weekly_accuracy.append({
            "accuracy": accuracy,
            "per_category": per_category or {},
            "week": len(self.weekly_accuracy) + 1,
        })

    def detect_trend(self, window=4):
        """
        Detect if accuracy is trending downward.

        Uses simple linear regression over the last N weeks.
        If the slope is negative and significant, alert.
        """
        if len(self.weekly_accuracy) < window:
            return {"trend": "insufficient_data", "slope": 0}

        recent = self.weekly_accuracy[-window:]
        # Simple slope calculation
        # slope = (y_end - y_start) / (x_end - x_start)
        x_values = list(range(window))
        y_values = [w["accuracy"] for w in recent]

        # Calculate slope using least squares (a math formula to find the trend line).
        # You don't need to memorize this formula - just know it finds the
        # "best fit line" through the data points, like a trend line in Excel.
        n = len(x_values)                    # how many data points
        sum_x = sum(x_values)                # add up all x values
        sum_y = sum(y_values)                # add up all y values
        # zip(x_values, y_values) pairs them: (0, 0.92), (1, 0.89), (2, 0.82)...
        # Then we multiply each pair (x * y) and add them all up.
        sum_xy = sum(x * y for x, y in zip(x_values, y_values))
        sum_x2 = sum(x * x for x in x_values)  # sum of x-squared values

        denominator = n * sum_x2 - sum_x * sum_x
        if denominator == 0:
            return {"trend": "flat", "slope": 0}

        slope = (n * sum_xy - sum_x * sum_y) / denominator

        # Interpret the slope
        if slope < -0.02:  # more than 2% drop per week
            trend = "declining_fast"
        elif slope < -0.005:  # more than 0.5% drop per week
            trend = "declining_slow"
        elif slope > 0.005:
            trend = "improving"
        else:
            trend = "stable"

        return {
            "trend": trend,
            "slope": round(slope, 4),
            "weeks_until_threshold": round(
                (recent[-1]["accuracy"] - 0.80) / abs(slope), 1
            ) if slope < 0 else None,
        }

    def find_degrading_categories(self):
        """Find which categories are degrading fastest."""
        if len(self.weekly_accuracy) < 4:
            return []

        first = self.weekly_accuracy[0]["per_category"]
        last = self.weekly_accuracy[-1]["per_category"]

        degrading = []
        for cat in first:
            if cat in last:
                drop = first[cat] - last[cat]
                if drop > 0.05:  # more than 5% drop
                    degrading.append({
                        "category": cat,
                        "start_accuracy": first[cat],
                        "current_accuracy": last[cat],
                        "drop": round(drop, 3),
                    })

        return sorted(degrading, key=lambda x: x["drop"], reverse=True)


# Simulate 12 weeks of data
monitor = AccuracyTrendMonitor()

for w in weekly_data:
    monitor.record_week(
        accuracy=w["accuracy"],
        per_category={
            "performance": w["performance"],
            "storage": w["storage"],
            "replication": w["replication"],
            "connectivity": w["connectivity"],
            "security": w["security"],
            "backup": w["backup"],
        }
    )

# Check trend
trend = monitor.detect_trend(window=4)
print(f"\n  Accuracy trend (last 4 weeks): {trend['trend']}")
print(f"  Slope: {trend['slope']} per week")
if trend.get("weeks_until_threshold"):
    print(f"  Weeks until 80% threshold: {trend['weeks_until_threshold']}")

# Find degrading categories
print(f"\n  Fastest Degrading Categories:")
for cat in monitor.find_degrading_categories():
    print(f"    {cat['category']}: {cat['start_accuracy']:.0%} -> {cat['current_accuracy']:.0%} (dropped {cat['drop']:.0%})")


print(f"""

Layer 3: Keyword Refresh Process
{'=' * 50}

When drift is detected, update keywords:

  1. Collect unknown words from drift detector
  2. Have senior DBA review and categorize them:
     - "patroni" -> replication
     - "switchover" -> replication
     - "pgbouncer" -> connectivity
     - "reserve pool" -> connectivity
  3. Add approved keywords to the model
  4. Run the test suite to verify improvement
  5. Deploy new version through normal pipeline

This is NOT an emergency. It's a maintenance task.
Schedule it weekly or when drift score exceeds 0.3.

Layer 4: Retraining Pipeline
{'=' * 50}

Monthly retraining process:
  1. Export all DBA-confirmed classifications (ground truth)
  2. Include corrections (DBA-corrected misclassifications)
  3. Update keyword lists based on new vocabulary
  4. Update metric thresholds based on new patterns
  5. Run full test suite (unit + integration + behavioral)
  6. Compare accuracy to current production model
  7. Deploy ONLY if accuracy improves (quality gate)

Prevention checklist:
  1. Monitor accuracy TRENDS, not just current values
  2. Track per-category accuracy (overall can hide problems)
  3. Detect vocabulary drift (new terms the model doesn't know)
  4. Schedule regular keyword reviews (weekly or monthly)
  5. Retrain on real production data (not just original training data)
  6. Quality gates prevent deploying worse models
  7. Alert when any category drops below 80% accuracy

DBA analogy:
  Model drift = index bloat. Performance degrades slowly.
  If you only check "is the query running?", you miss the bloat.
  You need: pg_stat_user_indexes + REINDEX schedule.
  Same for AI: accuracy monitoring + retraining schedule.
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Vocabulary drift | New tools change alert text, model can't classify | Drift detection + keyword refresh |
| No accuracy monitoring | Drift is invisible until DBAs lose trust | Per-category accuracy trends |
| Gradual degradation | 1-2% per week doesn't trigger alerts | Trend analysis over sliding window |
| No retraining process | Model frozen at launch-day knowledge | Monthly retraining on production data |
| Overall accuracy hides problems | 92% overall but 54% on replication | Per-category tracking with minimum thresholds |
