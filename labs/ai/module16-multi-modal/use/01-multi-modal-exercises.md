# Use 01: Multi-Modal AI Exercises

Practice combining multiple data types for better predictions.

---

## Exercise 1. Feature importance analysis

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re

# ============================================================
# Exercise: Figure out which features matter most.
#
# When you have 20+ features (text + metrics), not all are
# equally useful. Find the important ones.
#
# DBA analogy: like checking pg_stat_user_indexes.
# Some indexes are used constantly, others never.
# Drop the useless ones.
# ============================================================

print("Exercise 1: Feature Importance Analysis")
print("=" * 50)

class FeatureImportanceTracker:
    """
    Track which features contributed to correct predictions.

    Every time a feature is present AND the prediction is correct,
    that feature gets a point. Features with the most points
    are the most important.

    DBA analogy: like tracking which indexes are used.
    pg_stat_user_indexes.idx_scan tells you which indexes matter.
    We're building the same thing for features.
    """

    def __init__(self):
        self.feature_correct = {}    # feature -> times it helped
        self.feature_present = {}    # feature -> times it was present
        self.total_predictions = 0

    def record(self, features, was_correct):
        """
        Record which features were present and whether the prediction was right.

        features: dict of feature_name -> value
        was_correct: True if prediction matched actual
        """
        self.total_predictions += 1

        for name, value in features.items():
            if value > 0:                # feature is "present" (non-zero)
                # Count how often this feature appears
                self.feature_present[name] = self.feature_present.get(name, 0) + 1

                if was_correct:
                    # Count how often this feature helps get the right answer
                    self.feature_correct[name] = self.feature_correct.get(name, 0) + 1

    def get_importance(self):
        """
        Calculate importance score for each feature.

        importance = correct_rate * frequency
        A feature that is always right but rarely appears is less useful
        than one that is often right AND often appears.
        """
        importance = {}
        for name in self.feature_present:
            present = self.feature_present[name]
            correct = self.feature_correct.get(name, 0)
            frequency = present / self.total_predictions    # how often it appears
            accuracy = correct / present if present > 0 else 0  # how often it helps

            importance[name] = {
                "frequency": round(frequency, 3),
                "accuracy": round(accuracy, 3),
                "importance": round(frequency * accuracy, 3),
                "present": present,
                "correct": correct,
            }

        return dict(sorted(importance.items(),
                          key=lambda x: x[1]["importance"],
                          reverse=True))


# Simulate feature tracking
tracker = FeatureImportanceTracker()

# Training data with features and correctness
training_data = [
    # features, was_correct
    ({"text_cpu": 1, "text_slow": 1, "metric_cpu": 0.95}, True),
    ({"text_cpu": 1, "metric_cpu": 0.90}, True),
    ({"text_disk": 1, "text_full": 1, "metric_disk": 0.98}, True),
    ({"text_disk": 1, "metric_disk": 0.88}, True),
    ({"text_replication": 1, "text_lag": 1, "metric_repl_lag": 0.85}, True),
    ({"text_error": 1, "metric_cpu": 0.60}, False),           # "error" is vague
    ({"text_error": 1, "text_slow": 1, "metric_cpu": 0.92}, True),
    ({"text_connection": 1, "metric_connections": 0.90}, True),
    ({"text_error": 1, "metric_disk": 0.50}, False),          # "error" alone is unhelpful
    ({"text_cpu": 1, "text_slow": 1, "text_error": 1, "metric_cpu": 0.96}, True),
    ({"text_timeout": 1, "metric_connections": 0.85}, True),
    ({"text_slow": 1, "metric_cpu": 0.30}, False),            # text says slow but CPU fine
]

for features, correct in training_data:
    tracker.record(features, correct)

# Show results
importance = tracker.get_importance()

print(f"\nFeature Importance ({tracker.total_predictions} predictions):")
print("-" * 65)
print(f"{'Feature':<25s} {'Freq':>6s} {'Acc':>6s} {'Import':>8s} {'Present':>8s}")
print("-" * 65)

for name, stats in importance.items():
    bar = "#" * int(stats["importance"] * 40)
    print(f"{name:<25s} {stats['frequency']:>5.0%} {stats['accuracy']:>5.0%} "
          f"{stats['importance']:>7.3f}  {bar}")

print("""
Insights:
  - text_cpu + metric_cpu: high importance (frequent AND accurate)
  - text_error: low importance (frequent but often wrong alone)
  - text_full: medium importance (always accurate but less frequent)

Action: remove or downweight low-importance features.
  Like dropping unused indexes - less noise, faster queries.
""")
PYEOF
```

---

## Exercise 2. Confidence calibration

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# Exercise: Calibrate confidence scores.
#
# If your model says "90% confident" it should be right 90%
# of the time. If it says 90% but is only right 60%, the
# confidence is miscalibrated (overconfident).
#
# DBA analogy: if your monitoring says "99% uptime" but
# actual uptime is 95%, the monitoring is lying. Fix it.
# ============================================================

print("Exercise 2: Confidence Calibration")
print("=" * 50)

class ConfidenceCalibrator:
    """
    Check if model confidence matches actual accuracy.

    Bucket predictions by confidence range (0-50%, 50-70%, 70-90%, 90-100%).
    For each bucket, compare average confidence to actual accuracy.

    DBA analogy: like checking if your SLA metrics are accurate.
    If the dashboard says 99.9% but you had 3 outages, it's lying.
    """

    def __init__(self, num_buckets=5):
        """
        num_buckets: how many confidence ranges to create.
        5 buckets = 0-20%, 20-40%, 40-60%, 60-80%, 80-100%
        """
        self.num_buckets = num_buckets
        self.predictions = []            # list of (confidence, was_correct)

    def add(self, confidence, was_correct):
        """Record a prediction."""
        self.predictions.append((confidence, was_correct))

    def calibration_report(self):
        """
        Show accuracy per confidence bucket.

        A well-calibrated model:
          80-100% confidence bucket -> ~90% actual accuracy
          60-80% confidence bucket -> ~70% actual accuracy
          etc.
        """
        bucket_size = 1.0 / self.num_buckets

        report = []
        for i in range(self.num_buckets):
            low = i * bucket_size          # e.g., 0.0, 0.2, 0.4, ...
            high = (i + 1) * bucket_size   # e.g., 0.2, 0.4, 0.6, ...

            # Find predictions in this confidence range
            bucket_preds = [
                (conf, correct)
                for conf, correct in self.predictions
                if low <= conf < high or (i == self.num_buckets - 1 and conf == high)
            ]

            if bucket_preds:
                avg_conf = sum(c for c, _ in bucket_preds) / len(bucket_preds)
                actual_acc = sum(1 for _, c in bucket_preds if c) / len(bucket_preds)
                gap = avg_conf - actual_acc  # positive = overconfident
            else:
                avg_conf = 0
                actual_acc = 0
                gap = 0

            report.append({
                "range": f"{low:.0%}-{high:.0%}",
                "count": len(bucket_preds),
                "avg_confidence": round(avg_conf, 3),
                "actual_accuracy": round(actual_acc, 3),
                "gap": round(gap, 3),
            })

        return report


# Simulate predictions from a multi-modal model
import random
random.seed(42)

calibrator = ConfidenceCalibrator(num_buckets=5)

# Generate fake predictions
# The model is slightly overconfident (common problem)
for _ in range(200):
    true_quality = random.random()     # how "easy" this prediction is

    # Model confidence is inflated by 10-15%
    confidence = min(true_quality + random.uniform(0.05, 0.2), 1.0)

    # Actual correctness is based on true quality
    was_correct = random.random() < true_quality

    calibrator.add(confidence, was_correct)

# Show report
report = calibrator.calibration_report()

print(f"\nCalibration Report ({len(calibrator.predictions)} predictions):")
print("-" * 65)
print(f"{'Conf Range':<12s} {'Count':>6s} {'Avg Conf':>10s} {'Actual Acc':>11s} {'Gap':>6s} {'Status':<14s}")
print("-" * 65)

for r in report:
    if r["count"] == 0:
        status = "no data"
    elif abs(r["gap"]) < 0.05:
        status = "well calibrated"
    elif r["gap"] > 0:
        status = "OVERCONFIDENT"
    else:
        status = "underconfident"

    print(f"{r['range']:<12s} {r['count']:>6d} {r['avg_confidence']:>9.0%} "
          f"{r['actual_accuracy']:>10.0%} {r['gap']:>+5.0%}  {status}")

print("""
How to fix overconfidence:
  1. Temperature scaling: divide confidence by a constant (e.g., 1.2)
     conf_calibrated = conf_raw / 1.2
  2. Platt scaling: learn a mapping from raw confidence to calibrated
  3. Simply cap maximum confidence at 90% for multi-modal predictions

Why it matters:
  Overconfident predictions lead to auto-actions on wrong predictions.
  If the model says 95% but is only right 70%, your auto-pager
  sends false alarms 30% of the time. Calibration prevents this.
""")
PYEOF
```

---

## Exercise 3. Modality ablation study

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# Exercise: Ablation study - remove one modality at a time
# and see how accuracy changes. This tells you which
# modality is most valuable.
#
# DBA analogy: disable one monitoring tool at a time.
# - Without Grafana, can you still diagnose? (Yes, but slower)
# - Without logs, can you still diagnose? (Harder)
# - Without both, can you diagnose? (Barely)
# The tool that hurts most when removed is most valuable.
# ============================================================

print("Exercise 3: Modality Ablation Study")
print("=" * 50)

# Simple classifiers for each modality
def text_predict(text):
    rules = {
        "performance": ["cpu", "slow", "latency", "query"],
        "storage": ["disk", "space", "full", "wal"],
        "replication": ["replication", "lag", "standby"],
        "connectivity": ["connection", "timeout"],
    }
    text_lower = text.lower()
    for cat, kws in rules.items():
        if any(kw in text_lower for kw in kws):
            return cat
    return "unknown"

def metric_predict(metrics):
    rules = [
        ("cpu_percent", 85, "performance"),
        ("disk_percent", 85, "storage"),
        ("connections", 400, "connectivity"),
        ("replication_lag_seconds", 30, "replication"),
    ]
    for name, thresh, cat in rules:
        val = metrics.get(name)
        if val is not None and val >= thresh:
            return cat
    return "unknown"

def fusion_predict(text, metrics):
    t = text_predict(text)
    m = metric_predict(metrics)
    if t != "unknown":
        return t           # trust text when available
    return m

# Test dataset
test_data = [
    # (text, metrics, actual_category)
    ("CPU at 95% queries slow", {"cpu_percent": 95}, "performance"),
    ("Disk full on /pgdata", {"disk_percent": 98}, "storage"),
    ("Replication lag detected", {"replication_lag_seconds": 120}, "replication"),
    ("Connection timeout", {"connections": 450}, "connectivity"),
    ("Something seems slow", {"cpu_percent": 96}, "performance"),       # vague text
    ("Disk warning", {"cpu_percent": 30, "disk_percent": 60}, "storage"),  # metric misleading
    ("Server issue", {"cpu_percent": 92}, "performance"),               # vague text
    ("High latency reported", {"connections": 480}, "performance"),     # text correct, metric wrong
    ("WAL archive failing", {"disk_percent": 95}, "storage"),
    ("Standby not responding", {"replication_lag_seconds": 300}, "replication"),
]

# Run three experiments
modes = {
    "Text + Metrics (full)": lambda t, m: fusion_predict(t, m),
    "Text only (no metrics)": lambda t, m: text_predict(t),
    "Metrics only (no text)": lambda t, m: metric_predict(m),
}

print(f"\nAblation Study ({len(test_data)} test cases):")
print("-" * 50)

results = {}
for mode_name, predict_fn in modes.items():
    correct = 0
    for text, metrics, actual in test_data:
        predicted = predict_fn(text, metrics)
        if predicted == actual:
            correct += 1
    accuracy = correct / len(test_data) * 100
    results[mode_name] = accuracy
    bar = "#" * int(accuracy / 2)
    print(f"  {mode_name:<30s} {correct}/{len(test_data)} ({accuracy:.0f}%) {bar}")

# Analysis
full_acc = results["Text + Metrics (full)"]
text_acc = results["Text only (no metrics)"]
metric_acc = results["Metrics only (no text)"]

text_drop = full_acc - metric_acc       # how much accuracy drops without text
metric_drop = full_acc - text_acc       # how much accuracy drops without metrics

print(f"\nModality Value:")
print(f"  Removing text costs:    {text_drop:+.0f}% accuracy")
print(f"  Removing metrics costs: {metric_drop:+.0f}% accuracy")

if text_drop > metric_drop:
    print(f"\n  TEXT is more valuable (bigger accuracy drop when removed)")
else:
    print(f"\n  METRICS are more valuable (bigger accuracy drop when removed)")

print("""
Why ablation studies matter:
  1. Know which data source to prioritize (invest in better text or better metrics?)
  2. Know the graceful degradation path (if one source fails, how bad is it?)
  3. Justify the cost of each data pipeline (is the metric pipeline worth maintaining?)

DBA parallel: like testing "which monitoring tool can I NOT live without?"
""")
PYEOF
```

---

## Exercise 4. Cross-modal contradiction detection

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# Exercise: Detect when text and metrics CONTRADICT each other.
#
# If the text says "everything is fine" but CPU is at 99%,
# something is wrong. Either the text is lying or the
# metric is from the wrong server.
#
# DBA analogy: alert says "resolved" but the metric is
# still in the red. Trust the metric, investigate the text.
# ============================================================

print("Exercise 4: Cross-Modal Contradiction Detection")
print("=" * 50)

class ContradictionDetector:
    """
    Detect when text and metrics tell different stories.

    DBA analogy: like a consistency check between two data sources.
    SELECT * FROM alerts a
    JOIN metrics m ON a.server_id = m.server_id
    WHERE a.status = 'resolved' AND m.value > threshold;
    -- These shouldn't exist (resolved but still critical)
    """

    def __init__(self):
        # Text patterns and what they imply about metrics
        self.text_metric_expectations = [
            # (text_pattern, expected_metric, expected_direction)
            # If text says "cpu high", cpu_percent should be high (>80)
            (["cpu", "high", "spike"], "cpu_percent", "high", 80),
            (["cpu", "normal", "fine", "ok", "idle"], "cpu_percent", "low", 50),
            (["disk", "full", "space"], "disk_percent", "high", 80),
            (["disk", "ok", "plenty"], "disk_percent", "low", 50),
            (["replication", "lag"], "replication_lag_seconds", "high", 30),
            (["connection", "many", "pool"], "connections", "high", 300),
        ]

    def check(self, text, metrics):
        """
        Check for contradictions between text and metrics.
        Returns list of contradictions found.
        """
        text_lower = text.lower()
        contradictions = []

        for keywords, metric_name, direction, threshold in self.text_metric_expectations:
            # Check if text matches this pattern
            text_matches = any(kw in text_lower for kw in keywords)
            if not text_matches:
                continue

            # Check the corresponding metric
            metric_value = metrics.get(metric_name)
            if metric_value is None:
                continue                 # can't check without the metric

            # Does the metric match what the text implies?
            if direction == "high" and metric_value < threshold:
                contradictions.append({
                    "type": "text_says_high_metric_says_low",
                    "text_keywords": [kw for kw in keywords if kw in text_lower],
                    "metric": metric_name,
                    "metric_value": metric_value,
                    "expected": f">= {threshold}",
                    "severity": "warning",
                })
            elif direction == "low" and metric_value >= threshold:
                contradictions.append({
                    "type": "text_says_low_metric_says_high",
                    "text_keywords": [kw for kw in keywords if kw in text_lower],
                    "metric": metric_name,
                    "metric_value": metric_value,
                    "expected": f"< {threshold}",
                    "severity": "critical",  # metric overrides "everything is fine"
                })

        return contradictions


detector = ContradictionDetector()

test_cases = [
    # (text, metrics, description)
    ("CPU spike to 99%", {"cpu_percent": 99}, "Consistent: text and metric agree"),
    ("CPU spike detected", {"cpu_percent": 30}, "CONTRADICTION: text says high, metric says low"),
    ("Everything is fine, CPU normal", {"cpu_percent": 95}, "CONTRADICTION: text says fine, metric says high"),
    ("Disk is full, need cleanup", {"disk_percent": 98}, "Consistent: both say full"),
    ("Disk space is ok", {"disk_percent": 92}, "CONTRADICTION: text says ok, metric says full"),
    ("Replication lag increasing", {"replication_lag_seconds": 120}, "Consistent: lag confirmed"),
    ("Replication lag detected", {"replication_lag_seconds": 2}, "CONTRADICTION: text says lag, metric says fine"),
]

print("\nContradiction Detection Results:")
print("-" * 65)

for text, metrics, desc in test_cases:
    contradictions = detector.check(text, metrics)

    if contradictions:
        print(f"\n  CONTRADICTION: '{text}'")
        for c in contradictions:
            print(f"    {c['type']}")
            print(f"    {c['metric']}={c['metric_value']} (expected {c['expected']})")
            print(f"    Severity: {c['severity']}")
    else:
        print(f"\n  CONSISTENT: '{text}'")

print("""
When contradictions are found:
  1. Flag for human review (don't auto-classify)
  2. Trust metrics over text (metrics are measured, text is written by humans)
  3. Investigate the source (wrong server? stale alert? auto-generated text?)
  4. Log the contradiction (track how often each source is wrong)

DBA parallel: when the app says "connection successful" but pg_stat_activity
shows no connection from that IP, trust pg_stat_activity.
""")
PYEOF
```

---

## Exercise 5. End-to-end multi-modal pipeline

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
from datetime import datetime, timedelta

# ============================================================
# Exercise: Build a complete multi-modal classification pipeline.
#
# Input: raw alert (text + metrics + timestamp)
# Output: category + confidence + explanation
#
# Pipeline stages:
#   1. Extract features from text
#   2. Extract features from metrics
#   3. Align timestamps
#   4. Detect contradictions
#   5. Fuse predictions
#   6. Calibrate confidence
# ============================================================

print("Exercise 5: End-to-End Multi-Modal Pipeline")
print("=" * 55)

class MultiModalPipeline:
    """
    Complete multi-modal classification pipeline.

    DBA analogy: like a stored procedure that:
    1. Reads the alert
    2. Joins with metrics
    3. Validates consistency
    4. Classifies
    5. Returns result with confidence
    """

    def __init__(self):
        self.categories = ["performance", "storage", "replication", "connectivity", "unknown"]

    def _text_classify(self, text):
        rules = {
            "performance": ["cpu", "slow", "latency", "query"],
            "storage": ["disk", "space", "full", "wal"],
            "replication": ["replication", "lag", "standby"],
            "connectivity": ["connection", "timeout", "refused"],
        }
        text_lower = text.lower()
        best_cat, best_score = "unknown", 0
        for cat, kws in rules.items():
            score = sum(1 for kw in kws if kw in text_lower)
            if score > best_score:
                best_cat, best_score = cat, score
        conf = min(0.5 + best_score * 0.15, 0.85) if best_score > 0 else 0.15
        return best_cat, round(conf, 3)

    def _metric_classify(self, metrics):
        if not metrics:
            return "unknown", 0.15
        rules = [
            ("cpu_percent", 85, "performance"),
            ("disk_percent", 85, "storage"),
            ("connections", 400, "connectivity"),
            ("replication_lag_seconds", 30, "replication"),
        ]
        for name, thresh, cat in rules:
            val = metrics.get(name)
            if val is not None and val >= thresh:
                severity = min((val - thresh) / thresh, 1.0)
                return cat, round(0.5 + severity * 0.35, 3)
        return "unknown", 0.15

    def _check_contradiction(self, text, metrics):
        if not metrics:
            return False
        text_lower = text.lower()
        checks = [
            (["cpu", "high", "spike"], "cpu_percent", 80, "high"),
            (["cpu", "normal", "fine"], "cpu_percent", 50, "low"),
            (["disk", "full"], "disk_percent", 80, "high"),
        ]
        for kws, metric, thresh, direction in checks:
            if any(kw in text_lower for kw in kws):
                val = metrics.get(metric)
                if val is not None:
                    if direction == "high" and val < thresh:
                        return True
                    if direction == "low" and val >= thresh:
                        return True
        return False

    def classify(self, text, metrics=None):
        """
        Full pipeline: classify an alert using all available data.
        """
        result = {
            "text": text[:50],
            "has_metrics": metrics is not None and len(metrics) > 0,
        }

        # Step 1: Individual predictions
        text_cat, text_conf = self._text_classify(text)
        metric_cat, metric_conf = self._metric_classify(metrics or {})

        result["text_prediction"] = {"category": text_cat, "confidence": text_conf}
        result["metric_prediction"] = {"category": metric_cat, "confidence": metric_conf}

        # Step 2: Contradiction check
        has_contradiction = self._check_contradiction(text, metrics or {})
        result["contradiction"] = has_contradiction

        # Step 3: Fusion
        if has_contradiction:
            # Trust metrics when there's a contradiction
            final_cat = metric_cat if metric_conf > 0.3 else text_cat
            final_conf = max(text_conf, metric_conf) * 0.7  # reduce confidence
            result["fusion_note"] = "contradiction_detected - reduced confidence"
        elif text_cat == metric_cat and text_cat != "unknown":
            # Agreement
            final_cat = text_cat
            final_conf = min((text_conf + metric_conf) / 2 + 0.1, 0.95)
            result["fusion_note"] = "models_agree"
        elif not result["has_metrics"]:
            # Text only
            final_cat = text_cat
            final_conf = text_conf * 0.9  # slight penalty for missing data
            result["fusion_note"] = "text_only"
        else:
            # Disagreement without contradiction
            if text_conf >= metric_conf:
                final_cat = text_cat
            else:
                final_cat = metric_cat
            final_conf = max(text_conf, metric_conf) * 0.8
            result["fusion_note"] = "models_disagree"

        # Step 4: Calibrate (cap overconfidence)
        final_conf = min(final_conf, 0.95)

        result["final"] = {"category": final_cat, "confidence": round(final_conf, 3)}
        return result


# Test the pipeline
pipeline = MultiModalPipeline()

test_cases = [
    ("CPU at 95% queries slow", {"cpu_percent": 95}),
    ("Disk full on /pgdata", {"disk_percent": 98}),
    ("Replication lag 120s", {"replication_lag_seconds": 120}),
    ("CPU spike detected", {"cpu_percent": 30}),          # contradiction
    ("Everything is fine", {"cpu_percent": 96}),           # contradiction
    ("Server seems slow", None),                           # no metrics
    ("Unknown issue", {}),                                 # empty metrics
]

print("\nMulti-Modal Pipeline Results:")
print("-" * 70)

for text, metrics in test_cases:
    result = pipeline.classify(text, metrics)
    f = result["final"]
    note = result["fusion_note"]

    # Emoji-free status
    if result["contradiction"]:
        status = "CONTRADICTION"
    elif note == "models_agree":
        status = "AGREE"
    elif note == "text_only":
        status = "TEXT ONLY"
    else:
        status = "DISAGREE"

    print(f"  [{f['confidence']:>4.0%}] {f['category']:<15s} {status:<15s} '{text}'")

print("""
Pipeline stages:
  1. Text classifier -> category + confidence
  2. Metric classifier -> category + confidence
  3. Contradiction detector -> flag inconsistencies
  4. Fusion logic -> combine with appropriate strategy
  5. Confidence calibration -> cap at 95%

Production additions needed:
  - Time alignment (match alert to nearest metric snapshot)
  - Audit logging (record every decision)
  - A/B testing (compare fusion strategies)
""")
PYEOF
```

---

## What You Practiced

| Exercise | Skill | Production Use |
|----------|-------|---------------|
| Feature importance | Find which features matter | Drop useless features, save compute |
| Confidence calibration | Match confidence to accuracy | Reliable auto-actions |
| Ablation study | Measure each modality's value | Justify data pipeline costs |
| Contradiction detection | Find conflicting signals | Catch bad data, prevent wrong actions |
| End-to-end pipeline | Full multi-modal classification | Production-ready system |
