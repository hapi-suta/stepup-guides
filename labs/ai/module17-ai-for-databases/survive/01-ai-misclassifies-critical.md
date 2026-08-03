# Survive 01: AI Misclassifies a Critical Alert

The AI classified a "disk at 99% on production primary" as P3 (low priority) because the alert text said "routine disk check." The disk filled to 100% two hours later. Queries failed, WAL archiving stopped, and the database crashed.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime, timedelta

print("""
SCENARIO: AI Misclassifies Critical Alert

Timeline:
  14:00  Monitoring generates alert:
         "Routine disk check: /pgdata at 99% on pg-primary-prod"

  14:01  AI classifies it:
         Category: storage (correct)
         Severity: P3 - check next business day (WRONG!)

         WHY P3? The word "routine" in the text lowered the severity.
         The AI learned that "routine check" = low priority from
         training data where "routine" meant informational.

  14:02  Alert routed to low-priority queue. No one looks at it.

  15:30  Disk hits 100%. WAL can't be written.
         PostgreSQL enters read-only mode.
         All writes fail across 12 application servers.

  15:32  CASCADE of alerts fire:
         "FATAL: could not write to file pg_wal"
         "Connection refused: too many clients"
         "Application error: cannot INSERT"

  15:35  On-call paged (finally). Scrambles to free disk space.
  16:00  Service restored after 30 minutes of downtime.

POST-MORTEM:
  The AI had the right data (disk at 99%) but the wrong priority.
  The metric clearly said CRITICAL, but the text said "routine."
  The AI weighted text too heavily and ignored the metric severity.
""")

# Show the audit log
audit = {
    "alert_id": "alert_78234",
    "timestamp": "14:00:15",
    "text": "Routine disk check: /pgdata at 99% on pg-primary-prod",
    "metrics": {"disk_percent": 99, "wal_size_gb": 45},
    "ai_classification": {
        "category": "storage",
        "severity_score": 25,
        "priority": "P3",
        "text_signals": {"routine": -30, "disk": +10, "check": -10},
        "metric_signals": {"disk_percent_99": +90},
        "note": "Text penalty from 'routine' overrode metric severity",
    },
    "correct_classification": {
        "category": "storage",
        "severity_score": 95,
        "priority": "P1",
    },
    "impact": {
        "downtime_minutes": 30,
        "affected_services": 12,
        "estimated_cost": "$15,000",
    },
}

print("Audit Log:")
print(json.dumps(audit, indent=2))
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'

print("Investigation: Why the AI Got Severity Wrong")
print("=" * 55)

print("""
Root Cause: Text Signal Override

The AI's severity scorer works like this:
  base_score = max(metric_scores)     # 90 (disk at 99%)
  text_adjustment = sum(text_signals) # -30 ("routine" = -30, "check" = -10, "disk" = +10)
  final_score = base_score + text_adjustment  # 90 + (-30) = 60... but wait

ACTUAL BUG: The text adjustment was applied MULTIPLICATIVELY, not additively:
  final_score = base_score * (1 + text_adjustment/100)
  final_score = 90 * (1 + (-30)/100) = 90 * 0.7 = 63

  Then the environment weight was applied WRONG:
  The scorer used "production" weight 0.4 (it should have been 1.5)
  final_score = 63 * 0.4 = 25 -> P3

Three bugs combined:
  1. "routine" keyword had too much negative weight (-30)
  2. Text adjustments were multiplicative (should be additive with a cap)
  3. Environment weight lookup had a bug (production mapped to 0.4)

Any ONE of these bugs alone wouldn't have caused the misclassification.
All THREE together turned a P1 into a P3.
""")

# Demonstrate the bug
def buggy_scorer(metric_score, text_adjustment, env_weight):
    """The buggy scorer."""
    # Bug: multiplicative text adjustment
    adjusted = metric_score * (1 + text_adjustment / 100)
    # Bug: wrong environment weight
    final = adjusted * env_weight
    return round(final)

def fixed_scorer(metric_score, text_adjustment, env_weight):
    """The fixed scorer."""
    # Fix: additive adjustment, capped at +/- 20
    text_adj_capped = max(-20, min(20, text_adjustment))
    adjusted = metric_score + text_adj_capped
    # Fix: correct environment weight
    final = adjusted * env_weight
    # Fix: minimum floor based on metric severity
    # If ANY metric is critical (>90), minimum score is 80
    if metric_score >= 90:
        final = max(final, 80)
    return round(min(final, 100))

print("Buggy scorer:")
print(f"  metric=90, text=-30, env=0.4 -> {buggy_scorer(90, -30, 0.4)} (P3)")

print(f"\nFixed scorer:")
print(f"  metric=90, text=-30, env=1.5 -> {fixed_scorer(90, -30, 1.5)} (P1)")

print("""
Three fixes:
  1. Cap text adjustments at +/- 20 (text can nudge, not override)
  2. Fix environment weight lookup (production = 1.5, not 0.4)
  3. Add metric floor: if any metric is critical, minimum score = 80
     (a metric at 99% CANNOT be P3, regardless of text)
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'

print("""
FIX: Four layers of protection against severity misclassification.

Layer 1: Metric floor (critical metrics force minimum severity)
Layer 2: Text adjustment cap (text can nudge, not override)
Layer 3: Override rules (hardcoded rules for critical scenarios)
Layer 4: Human-in-the-loop for high-severity decisions
""")

print("Layer 1: Metric Floor")
print("=" * 50)

class SafeSeverityScorer:
    """
    Severity scorer with safety floors.

    Key rule: if any metric is in the critical range,
    the severity score CANNOT go below 80 (P1).

    DBA analogy: if disk is at 99%, it doesn't matter what
    the text says. 99% is 99%. The number overrides the words.
    """

    def __init__(self):
        self.critical_thresholds = {
            "disk_percent": 95,
            "cpu_percent": 98,
            "connection_percent": 95,
            "replication_lag_seconds": 600,
        }
        self.env_weights = {"production": 1.5, "staging": 1.0, "development": 0.5}

    def score(self, metrics, text_adjustment=0, environment="production"):
        # Step 1: Score metrics
        metric_score = 0
        has_critical = False

        for metric_name, value in metrics.items():
            critical_thresh = self.critical_thresholds.get(metric_name)
            if critical_thresh and value >= critical_thresh:
                has_critical = True
                metric_score = max(metric_score, 90)
            elif critical_thresh and value >= critical_thresh * 0.85:
                metric_score = max(metric_score, 70)

        # Step 2: Apply text adjustment (CAPPED)
        capped_adjustment = max(-20, min(20, text_adjustment))
        adjusted = metric_score + capped_adjustment

        # Step 3: Apply environment weight
        env_weight = self.env_weights.get(environment, 1.0)
        final = adjusted * env_weight

        # Step 4: METRIC FLOOR - critical metric = minimum 80
        if has_critical and environment == "production":
            final = max(final, 80)

        final = max(0, min(100, final))

        # Assign priority
        if final >= 80: priority = "P1"
        elif final >= 60: priority = "P2"
        elif final >= 30: priority = "P3"
        else: priority = "P4"

        return {
            "score": round(final),
            "priority": priority,
            "metric_score": metric_score,
            "text_adjustment": capped_adjustment,
            "has_critical_metric": has_critical,
            "environment": environment,
        }


scorer = SafeSeverityScorer()

test_cases = [
    # The original failure case
    ("Routine disk check at 99%", {"disk_percent": 99}, -30, "production"),
    # Normal cases
    ("Disk warning at 82%", {"disk_percent": 82}, 0, "production"),
    ("CPU critical at 98%", {"cpu_percent": 98}, 0, "production"),
    # Text trying to downplay
    ("Normal CPU check", {"cpu_percent": 99}, -30, "production"),
    # Dev environment (should still flag critical metrics, lower priority)
    ("Disk at 96% on dev", {"disk_percent": 96}, 0, "development"),
]

print(f"\nSafe Severity Scoring:")
print("-" * 75)
print(f"{'Description':<35s} {'Score':>6s} {'Priority':>8s} {'Critical?':>10s} {'TextAdj':>8s}")
print("-" * 75)

for desc, metrics, text_adj, env in test_cases:
    result = scorer.score(metrics, text_adj, env)
    print(f"{desc:<35s} {result['score']:>6d} {result['priority']:>8s} "
          f"{'YES' if result['has_critical_metric'] else 'no':>10s} "
          f"{result['text_adjustment']:>+7d}")

print("""
Layer 2: Override Rules (hardcoded safety)
  - disk >= 95% on production -> ALWAYS P1 (no override possible)
  - CPU >= 98% on production -> ALWAYS P1
  - Replication lag > 10 min on production -> ALWAYS P1
  These are non-negotiable. No amount of text can change them.

Layer 3: Human-in-the-Loop
  - Any P1 alert gets paged to on-call AND logged for review
  - Any alert where text and metrics disagree gets flagged
  - Weekly review of severity scoring accuracy

Layer 4: Regression Tests
  - "Routine disk check at 99%" MUST score P1 (test added)
  - Every past misclassification becomes a test case
  - Deployment blocked if any severity test fails

Prevention checklist:
  1. Critical metrics always force minimum severity (floor rule)
  2. Text adjustments are capped (can't override metrics)
  3. Environment weights are verified (unit test)
  4. Past misclassifications become regression tests
  5. Weekly severity accuracy review
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Text overrides metric severity | "Routine" turned P1 into P3 | Cap text adjustments, add metric floor |
| Wrong environment weight | Production mapped to 0.4 | Unit test all weight mappings |
| No safety floor | Critical metric can be downgraded | Critical metric = minimum P1 |
| No regression tests | Same bug can happen again | Every misclassification = test case |
| No human review | AI severity trusted blindly | Weekly accuracy review |
