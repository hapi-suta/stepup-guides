# Build 02: Late Fusion - Combine Separate Models

Late fusion means each data type gets its own model, then you combine the predictions at the end. Each model is a specialist.

---

## Step 1. Text-only classifier

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re

# ============================================================
# TEXT-ONLY CLASSIFIER
# A model that only looks at the alert text.
#
# DBA analogy: diagnosing based ONLY on the error message,
# without looking at any metrics or dashboards.
# ============================================================

print("Text-Only Classifier")
print("=" * 50)

class TextClassifier:
    """
    Classify alerts using only the text content.

    DBA analogy: like a junior DBA who only reads error messages.
    They can handle obvious cases ("disk full" = storage) but
    miss subtle ones that need metrics to diagnose.
    """

    def __init__(self):
        # Keyword rules: if ANY keyword matches, assign that category
        # Each category has a list of words to look for
        self.rules = {
            "performance": ["cpu", "slow", "latency", "query", "lock", "wait"],
            "storage": ["disk", "space", "full", "tablespace", "wal", "archive"],
            "replication": ["replication", "lag", "standby", "replica", "failover"],
            "security": ["login", "password", "ssl", "auth", "permission", "denied"],
            "connectivity": ["connection", "timeout", "refused", "unreachable", "dns"],
            "backup": ["backup", "restore", "pitr", "basebackup", "pg_dump"],
        }

    def predict(self, text):
        """
        Predict category from text.
        Returns (category, confidence).

        Higher confidence when more keywords match.
        """
        text_lower = text.lower()
        scores = {}                      # category -> number of keyword matches

        for category, keywords in self.rules.items():
            # Count how many keywords from this category appear in the text.
            # sum(1 for kw in keywords if kw in text_lower) means:
            #   "for each keyword, add 1 if it appears in the text"
            # So if 3 out of 6 keywords appear, matches = 3.
            # DBA analogy: SELECT COUNT(*) FROM keywords WHERE keyword IN (text_words)
            matches = sum(1 for kw in keywords if kw in text_lower)
            if matches > 0:
                scores[category] = matches

        if not scores:
            return "unknown", 0.2        # no keywords matched

        # Pick the category with the most keyword matches.
        # max(scores, key=scores.get) finds the key with the highest value.
        # scores.get is passed WITHOUT () - we're giving max() the function
        # itself, and max() calls it on each key to compare them.
        # DBA analogy: SELECT category FROM scores ORDER BY count DESC LIMIT 1
        best_category = max(scores, key=scores.get)
        best_score = scores[best_category]

        # Convert match count to confidence (0-1)
        # 1 match = 0.6, 2 matches = 0.75, 3+ matches = 0.85
        confidence = min(0.5 + best_score * 0.15, 0.9)

        return best_category, round(confidence, 3)

# Test
text_model = TextClassifier()

test_texts = [
    "CPU at 95% - queries running slow",
    "Disk full on /pgdata partition",
    "Replication lag 120 seconds",
    "Connection timeout from application",
    "Something strange happened",
    "SSL certificate expiring soon",
]

print("\nText Model Predictions:")
print("-" * 50)
for text in test_texts:
    # Tuple unpacking: predict() returns TWO values (category, confidence).
    # This line catches both at once, like: SELECT cat, conf INTO var1, var2
    category, confidence = text_model.predict(text)
    # Format specifiers in f-strings:
    #   {confidence:.0%} = show as percentage with 0 decimal places (0.85 -> "85%")
    #   {category:<15s}  = left-align text, padded to 15 characters wide
    print(f"  [{confidence:.0%}] {category:<15s} <- '{text}'")

PYEOF
```

---

## Step 2. Metric-only classifier

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# METRIC-ONLY CLASSIFIER
# A model that only looks at the numeric metrics.
#
# DBA analogy: diagnosing based ONLY on Grafana dashboards,
# without reading any log messages.
# ============================================================

print("Metric-Only Classifier")
print("=" * 50)

class MetricClassifier:
    """
    Classify alerts using only numeric metrics.

    DBA analogy: like looking at only the Grafana dashboard.
    You see CPU is high but don't know WHY. The text
    might say "vacuum running" which changes the diagnosis.
    """

    def __init__(self):
        # Threshold rules: if metric exceeds threshold, flag that category
        # format: (metric_name, threshold, category, severity_weight)
        self.rules = [
            ("cpu_percent", 85, "performance", 0.8),
            ("cpu_percent", 95, "performance", 0.95),
            ("memory_percent", 90, "performance", 0.85),
            ("disk_percent", 85, "storage", 0.8),
            ("disk_percent", 95, "storage", 0.95),
            ("connections", 400, "connectivity", 0.8),
            ("connections", 480, "connectivity", 0.95),
            ("replication_lag_seconds", 30, "replication", 0.7),
            ("replication_lag_seconds", 120, "replication", 0.9),
            ("query_latency_ms", 5000, "performance", 0.75),
            ("query_latency_ms", 15000, "performance", 0.9),
        ]

    def predict(self, metrics):
        """
        Predict category from metrics.
        Returns (category, confidence).

        Checks each metric against thresholds.
        Multiple triggered rules increase confidence.
        """
        triggered = []                   # list of (category, weight) that fired

        for metric_name, threshold, category, weight in self.rules:
            value = metrics.get(metric_name)
            if value is not None and value >= threshold:
                triggered.append((category, weight))

        if not triggered:
            return "unknown", 0.2

        # Group by category, take the highest weight per category
        category_scores = {}
        for category, weight in triggered:
            if category not in category_scores or weight > category_scores[category]:
                category_scores[category] = weight

        # Pick the category with the highest score
        best_category = max(category_scores, key=category_scores.get)
        best_score = category_scores[best_category]

        return best_category, round(best_score, 3)

# Test
metric_model = MetricClassifier()

test_metrics = [
    {"cpu_percent": 95, "memory_percent": 60, "connections": 150},
    {"disk_percent": 98, "cpu_percent": 30},
    {"replication_lag_seconds": 120, "cpu_percent": 45},
    {"connections": 490, "cpu_percent": 80},
    {"cpu_percent": 40, "memory_percent": 50},   # everything normal
]

labels = [
    "High CPU, normal memory",
    "High disk, low CPU",
    "High repl lag",
    "High connections + CPU",
    "Everything normal",
]

print("\nMetric Model Predictions:")
print("-" * 50)
# zip() pairs up items from two lists by position:
#   zip([metrics1, metrics2], [label1, label2])
#   gives: (metrics1, label1), (metrics2, label2)
# DBA analogy: like joining two arrays by index position.
for metrics, label in zip(test_metrics, labels):
    category, confidence = metric_model.predict(metrics)
    print(f"  [{confidence:.0%}] {category:<15s} <- {label}")

PYEOF
```

---

## Step 3. Late fusion - combine both models

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re

# ============================================================
# LATE FUSION CLASSIFIER
# Combine text model + metric model predictions.
#
# DBA analogy: two DBAs each diagnose independently.
# Then they compare notes and agree on the final answer.
# The more experienced DBA (higher confidence) gets more weight.
# ============================================================

print("Late Fusion: Combining Two Models")
print("=" * 50)

class TextClassifier:
    """Text-only classifier (from Step 1)."""
    def __init__(self):
        self.rules = {
            "performance": ["cpu", "slow", "latency", "query", "lock", "wait"],
            "storage": ["disk", "space", "full", "tablespace", "wal"],
            "replication": ["replication", "lag", "standby", "replica"],
            "security": ["login", "password", "ssl", "auth", "denied"],
            "connectivity": ["connection", "timeout", "refused"],
            "backup": ["backup", "restore", "pitr", "basebackup"],
        }

    def predict(self, text):
        text_lower = text.lower()
        scores = {}
        for category, keywords in self.rules.items():
            matches = sum(1 for kw in keywords if kw in text_lower)
            if matches > 0:
                scores[category] = matches
        if not scores:
            return "unknown", 0.2
        best = max(scores, key=scores.get)
        conf = min(0.5 + scores[best] * 0.15, 0.9)
        return best, round(conf, 3)


class MetricClassifier:
    """Metric-only classifier (from Step 2)."""
    def __init__(self):
        self.rules = [
            ("cpu_percent", 85, "performance", 0.8),
            ("cpu_percent", 95, "performance", 0.95),
            ("disk_percent", 85, "storage", 0.8),
            ("disk_percent", 95, "storage", 0.95),
            ("connections", 400, "connectivity", 0.8),
            ("replication_lag_seconds", 30, "replication", 0.7),
            ("replication_lag_seconds", 120, "replication", 0.9),
        ]

    def predict(self, metrics):
        triggered = []
        for name, thresh, cat, weight in self.rules:
            val = metrics.get(name)
            if val is not None and val >= thresh:
                triggered.append((cat, weight))
        if not triggered:
            return "unknown", 0.2
        cat_scores = {}
        for cat, w in triggered:
            if cat not in cat_scores or w > cat_scores[cat]:
                cat_scores[cat] = w
        best = max(cat_scores, key=cat_scores.get)
        return best, round(cat_scores[best], 3)


class LateFusionClassifier:
    """
    Combine text and metric predictions using weighted voting.

    DBA analogy: two DBAs diagnose independently, then compare.
    If they agree -> high confidence.
    If they disagree -> go with the more confident one, but lower overall confidence.

    Like two database health checks that must agree before paging:
      pg_stat_activity says "problem" + Grafana says "problem" = definitely page
      pg_stat_activity says "fine" + Grafana says "problem" = investigate first
    """

    def __init__(self, text_weight=0.5, metric_weight=0.5):
        """
        text_weight: how much to trust the text model (0 to 1)
        metric_weight: how much to trust the metric model (0 to 1)
        They should add up to 1.0.
        """
        self.text_model = TextClassifier()
        self.metric_model = MetricClassifier()
        self.text_weight = text_weight       # trust text this much
        self.metric_weight = metric_weight   # trust metrics this much

    def predict(self, text, metrics):
        """
        Get predictions from both models and combine them.
        Returns (category, confidence, explanation).
        """
        # Get each model's prediction
        text_cat, text_conf = self.text_model.predict(text)
        metric_cat, metric_conf = self.metric_model.predict(metrics)

        # Case 1: Both models agree on category
        if text_cat == metric_cat:
            # Agreement! Boost confidence.
            # Weighted average of confidences, with a bonus for agreement
            combined_conf = (
                self.text_weight * text_conf +
                self.metric_weight * metric_conf
            )
            # Bonus: agreement means we're more sure
            combined_conf = min(combined_conf + 0.1, 1.0)

            return text_cat, round(combined_conf, 3), "both_agree"

        # Case 2: Models disagree
        # Go with the more confident model, but reduce overall confidence
        text_score = text_conf * self.text_weight
        metric_score = metric_conf * self.metric_weight

        if text_score >= metric_score:
            winner = text_cat
            combined_conf = text_score    # no agreement bonus
        else:
            winner = metric_cat
            combined_conf = metric_score

        # Penalty: disagreement means uncertainty
        combined_conf = max(combined_conf - 0.1, 0.1)

        return winner, round(combined_conf, 3), "models_disagree"

    def predict_detailed(self, text, metrics):
        """Same as predict but returns full breakdown."""
        text_cat, text_conf = self.text_model.predict(text)
        metric_cat, metric_conf = self.metric_model.predict(metrics)
        final_cat, final_conf, agreement = self.predict(text, metrics)

        return {
            "text_prediction": {"category": text_cat, "confidence": text_conf},
            "metric_prediction": {"category": metric_cat, "confidence": metric_conf},
            "final_prediction": {"category": final_cat, "confidence": final_conf},
            "agreement": agreement,
        }


# Test the fusion
fusion = LateFusionClassifier(text_weight=0.5, metric_weight=0.5)

test_cases = [
    # (text, metrics, description)
    (
        "CPU at 95% - queries running slow",
        {"cpu_percent": 95, "memory_percent": 60},
        "Both agree: performance"
    ),
    (
        "Disk full on /pgdata",
        {"disk_percent": 98, "cpu_percent": 30},
        "Both agree: storage"
    ),
    (
        "Something seems slow",
        {"cpu_percent": 96},
        "Text unsure, metrics clear"
    ),
    (
        "Replication lag detected on standby",
        {"cpu_percent": 92},
        "Text says replication, metrics say performance"
    ),
    (
        "Unknown issue on server",
        {"cpu_percent": 40, "disk_percent": 50},
        "Neither model confident"
    ),
]

print("\nLate Fusion Results:")
print("-" * 65)

for text, metrics, description in test_cases:
    result = fusion.predict_detailed(text, metrics)
    tp = result["text_prediction"]
    mp = result["metric_prediction"]
    fp = result["final_prediction"]

    print(f"\n  Scenario: {description}")
    print(f"    Text model:   {tp['category']:<15s} ({tp['confidence']:.0%})")
    print(f"    Metric model: {mp['category']:<15s} ({mp['confidence']:.0%})")
    print(f"    FUSION:       {fp['category']:<15s} ({fp['confidence']:.0%}) [{result['agreement']}]")

print("""

How Late Fusion Works:
  1. Each model predicts independently
  2. If they AGREE -> boost confidence (both see the same thing)
  3. If they DISAGREE -> go with more confident one, reduce confidence
  4. Weights control which model you trust more

When to adjust weights:
  - text_weight=0.7, metric_weight=0.3 -> trust text more (good alert messages)
  - text_weight=0.3, metric_weight=0.7 -> trust metrics more (noisy text)
  - text_weight=0.5, metric_weight=0.5 -> equal trust (default)
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Text classifier | Predict from words only | Diagnosis from error message |
| Metric classifier | Predict from numbers only | Diagnosis from Grafana |
| Late fusion | Combine two predictions | Two DBAs compare notes |
| Agreement boost | Higher confidence when models agree | Both checks flag the same issue |
| Disagreement penalty | Lower confidence when models conflict | Conflicting signals = investigate more |
| Model weights | Control trust per model | Trust experienced DBA more |
