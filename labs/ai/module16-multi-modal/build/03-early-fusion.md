# Build 03: Early Fusion - Combine Features First

Early fusion merges all features into one vector before making a prediction. One model sees everything at once.

---

## Step 1. Feature concatenation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
import math

# ============================================================
# EARLY FUSION: FEATURE CONCATENATION
# Merge text features and metric features into one list,
# then feed that one list to a single model.
#
# DBA analogy: instead of two separate tables (alerts + metrics),
# create one denormalized table with ALL columns.
# SELECT * FROM alerts JOIN metrics USING (alert_id);
# One row, all the data, one query to analyze.
# ============================================================

print("Early Fusion: Feature Concatenation")
print("=" * 50)

class EarlyFusionExtractor:
    """
    Combine text and metric features into one feature vector.

    A feature vector is just a list of numbers.
    Each position in the list means something specific.

    DBA analogy: a denormalized table row.
    columns = [has_cpu, has_disk, ..., cpu_scaled, disk_scaled, ...]
    values  = [1,       0,        ..., 0.95,       0.30,        ...]
    """

    def __init__(self):
        # Text keywords to check (order matters - position = feature index)
        self.keywords = [
            "cpu", "memory", "disk", "replication",
            "lag", "full", "slow", "error",
            "timeout", "connection",
        ]

        # Metric names and their expected ranges (for scaling)
        self.metrics_config = [
            ("cpu_percent", 0, 100),
            ("memory_percent", 0, 100),
            ("disk_percent", 0, 100),
            ("connections", 0, 500),
            ("replication_lag_seconds", 0, 3600),
            ("query_latency_ms", 0, 30000),
        ]

    def extract(self, text, metrics):
        """
        Convert text + metrics into one feature vector (list of numbers).

        Returns:
          features: list of floats
          feature_names: list of strings (what each position means)
        """
        features = []       # the numbers
        names = []          # what each number means

        # --- Text features ---
        text_lower = text.lower()
        for kw in self.keywords:
            # 1.0 if keyword present, 0.0 if not
            features.append(1.0 if kw in text_lower else 0.0)
            names.append(f"text_{kw}")

        # Text length feature (normalized by dividing by 200)
        word_count = len(re.findall(r'[a-z0-9]+', text_lower))
        features.append(min(word_count / 20.0, 1.0))  # cap at 1.0
        names.append("text_length")

        # --- Metric features ---
        for metric_name, min_val, max_val in self.metrics_config:
            value = metrics.get(metric_name)

            if value is not None:
                # Scale to 0-1
                range_val = max_val - min_val
                scaled = (value - min_val) / range_val if range_val > 0 else 0
                scaled = max(0.0, min(1.0, scaled))    # clamp to 0-1
                features.append(round(scaled, 4))
                names.append(f"metric_{metric_name}")

                # Missing flag = 0 (not missing)
                features.append(0.0)
                names.append(f"missing_{metric_name}")
            else:
                # Missing metric: value = 0, flag = 1
                features.append(0.0)
                names.append(f"metric_{metric_name}")
                features.append(1.0)                   # missing!
                names.append(f"missing_{metric_name}")

        return features, names

# Test it
extractor = EarlyFusionExtractor()

test_alert = {
    "text": "CPU at 95% - queries running slow",
    "metrics": {"cpu_percent": 95, "memory_percent": 60, "disk_percent": 42},
}

features, names = extractor.extract(test_alert["text"], test_alert["metrics"])

print(f"\nAlert: '{test_alert['text']}'")
print(f"Metrics: {test_alert['metrics']}")
print(f"\nFeature vector ({len(features)} features):")
print("-" * 50)

for name, value in zip(names, features):
    if value != 0:                       # only show non-zero features
        bar = "#" * int(value * 20)      # visual bar
        print(f"  {name:<30s} {value:>6.3f} {bar}")

print(f"\nTotal features: {len(features)}")
print(f"  Text features: {sum(1 for n in names if n.startswith('text_'))}")
print(f"  Metric features: {sum(1 for n in names if n.startswith('metric_'))}")
print(f"  Missing flags: {sum(1 for n in names if n.startswith('missing_'))}")

PYEOF
```

---

## Step 2. Single model on combined features

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
import math

# ============================================================
# EARLY FUSION CLASSIFIER
# One model that sees ALL features (text + metrics) at once.
#
# DBA analogy: one expert DBA who looks at EVERYTHING together -
# the error message, the metrics, and how they relate.
# They might notice that "slow query" + high CPU + normal disk
# is different from "slow query" + normal CPU + full disk.
# ============================================================

print("Early Fusion Classifier")
print("=" * 50)

class EarlyFusionClassifier:
    """
    Classify using combined text + metric features.

    Instead of keyword rules or threshold rules separately,
    this model uses WEIGHTED FEATURES - each feature has a
    weight per category. The category with the highest total
    weighted score wins.

    DBA analogy: like a scoring matrix.
    Each symptom (feature) contributes points to each diagnosis (category).
    The diagnosis with the most points wins.

    Feature          | Performance | Storage | Replication | Connectivity
    ---------------+-----------+---------+-------------+-------------
    has_cpu = 1     |    +3      |    0    |      0      |      0
    has_disk = 1    |     0      |   +3    |      0      |      0
    cpu_high        |    +2      |    0    |      0      |     +1
    disk_high       |     0      |   +2    |      0      |      0
    """

    def __init__(self):
        self.keywords = [
            "cpu", "memory", "disk", "replication",
            "lag", "full", "slow", "error",
            "timeout", "connection",
        ]
        self.metrics_config = [
            ("cpu_percent", 0, 100),
            ("memory_percent", 0, 100),
            ("disk_percent", 0, 100),
            ("connections", 0, 500),
            ("replication_lag_seconds", 0, 3600),
        ]

        # Weight matrix: feature_index -> {category: weight}
        # Positive weight = evidence FOR this category
        # Negative weight = evidence AGAINST this category
        # These weights would be LEARNED in a real ML model.
        # Here we set them manually for clarity.
        self.categories = ["performance", "storage", "replication", "connectivity", "unknown"]

        # Weights for text keywords
        # Index matches self.keywords order
        self.text_weights = {
            # keyword      perf  stor  repl  conn  unkn
            "cpu":        [ 3.0,  0.0,  0.0,  0.0, -1.0],
            "memory":     [ 2.0,  0.0,  0.0,  0.0, -1.0],
            "disk":       [ 0.0,  3.0,  0.0,  0.0, -1.0],
            "replication":[ 0.0,  0.0,  3.0,  0.0, -1.0],
            "lag":        [ 0.5,  0.0,  2.5,  0.0, -1.0],
            "full":       [ 0.0,  2.5,  0.0,  0.0, -1.0],
            "slow":       [ 2.5,  0.0,  0.0,  0.5, -1.0],
            "error":      [ 0.5,  0.5,  0.5,  0.5,  0.0],
            "timeout":    [ 0.5,  0.0,  0.0,  2.5, -1.0],
            "connection": [ 0.0,  0.0,  0.0,  3.0, -1.0],
        }

        # Weights for metric values (applied to scaled 0-1 values)
        self.metric_weights = {
            # metric               perf  stor  repl  conn  unkn
            "cpu_percent":        [ 2.0,  0.0,  0.0,  0.5,  0.0],
            "memory_percent":     [ 1.5,  0.0,  0.0,  0.0,  0.0],
            "disk_percent":       [ 0.0,  2.5,  0.0,  0.0,  0.0],
            "connections":        [ 0.5,  0.0,  0.0,  2.0,  0.0],
            "replication_lag_seconds": [0.0, 0.0, 2.5, 0.0, 0.0],
        }

    def _extract_features(self, text, metrics):
        """Extract and scale features."""
        text_lower = text.lower()

        # Text features: 1.0 if keyword present, 0.0 if not
        text_features = {}
        for kw in self.keywords:
            text_features[kw] = 1.0 if kw in text_lower else 0.0

        # Metric features: scaled to 0-1
        metric_features = {}
        for name, min_v, max_v in self.metrics_config:
            val = metrics.get(name)
            if val is not None:
                scaled = (val - min_v) / (max_v - min_v) if (max_v - min_v) > 0 else 0
                metric_features[name] = max(0.0, min(1.0, scaled))
            else:
                metric_features[name] = 0.0

        return text_features, metric_features

    def predict(self, text, metrics):
        """
        Score each category using weighted features.

        Score = sum of (feature_value * feature_weight) for each feature.
        The category with the highest score wins.
        """
        text_feats, metric_feats = self._extract_features(text, metrics)

        # Calculate score for each category
        scores = {cat: 0.0 for cat in self.categories}

        # Add text feature contributions
        for kw, value in text_feats.items():
            if value > 0 and kw in self.text_weights:
                weights = self.text_weights[kw]
                for i, cat in enumerate(self.categories):
                    scores[cat] += value * weights[i]

        # Add metric feature contributions
        for metric_name, value in metric_feats.items():
            if value > 0.5 and metric_name in self.metric_weights:
                # Only count metrics above 50% (above "normal")
                weights = self.metric_weights[metric_name]
                for i, cat in enumerate(self.categories):
                    scores[cat] += value * weights[i]

        # Convert scores to confidence using softmax-like normalization
        # First, find the max score
        max_score = max(scores.values())

        if max_score <= 0:
            return "unknown", 0.2, scores

        # Normalize: divide each by the sum of all positive scores
        positive_scores = {k: v for k, v in scores.items() if v > 0}
        total = sum(positive_scores.values())

        if total == 0:
            return "unknown", 0.2, scores

        # Best category = highest score
        best_cat = max(scores, key=scores.get)
        confidence = scores[best_cat] / total  # proportion of total score

        return best_cat, round(confidence, 3), scores

# Test it
model = EarlyFusionClassifier()

test_cases = [
    (
        "CPU at 95% - queries running slow",
        {"cpu_percent": 95, "memory_percent": 60},
        "Performance: text + metrics agree"
    ),
    (
        "Disk full on /pgdata",
        {"disk_percent": 98, "cpu_percent": 30},
        "Storage: text + metrics agree"
    ),
    (
        "Something seems slow",
        {"cpu_percent": 96},
        "Vague text, clear metrics"
    ),
    (
        "Replication lag on standby",
        {"replication_lag_seconds": 120, "cpu_percent": 45},
        "Replication: text + metrics"
    ),
    (
        "Connection timeout from app",
        {"connections": 490, "cpu_percent": 85},
        "Mixed signals: connectivity + performance"
    ),
]

print("\nEarly Fusion Results:")
print("-" * 65)

for text, metrics, description in test_cases:
    category, confidence, scores = model.predict(text, metrics)

    # Get top 2 scores for display
    sorted_scores = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    top2 = sorted_scores[:2]

    print(f"\n  {description}")
    print(f"    Text:    '{text}'")
    print(f"    Metrics: {metrics}")
    print(f"    Result:  {category} ({confidence:.0%})")
    print(f"    Scores:  {top2[0][0]}={top2[0][1]:.1f}, {top2[1][0]}={top2[1][1]:.1f}")

print("""

How Early Fusion Differs from Late Fusion:
  Late fusion:  text model + metric model -> combine predictions
  Early fusion: combine features -> one model -> one prediction

Early fusion advantage:
  The model sees CROSS-MODAL patterns.
  "slow" (text) + high CPU (metric) = performance
  "slow" (text) + full disk (metric) = storage
  Same word, different diagnosis based on metrics!

Late fusion advantage:
  Easier to debug. You know which model said what.
  Easier to add/remove modalities.
""")
PYEOF
```

---

## Step 3. Compare early vs late fusion

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re

# ============================================================
# COMPARE EARLY VS LATE FUSION
# Run both approaches on the same test cases.
# See where each approach excels or fails.
#
# DBA analogy:
# Early fusion = one senior DBA who sees everything
# Late fusion = two specialists who compare notes
# ============================================================

print("Early vs Late Fusion Comparison")
print("=" * 55)

# --- Late Fusion (from Build 02) ---
class TextClassifier:
    def __init__(self):
        self.rules = {
            "performance": ["cpu", "slow", "latency", "query"],
            "storage": ["disk", "space", "full", "tablespace", "wal"],
            "replication": ["replication", "lag", "standby"],
            "connectivity": ["connection", "timeout", "refused"],
        }
    def predict(self, text):
        text_lower = text.lower()
        scores = {}
        for cat, kws in self.rules.items():
            m = sum(1 for kw in kws if kw in text_lower)
            if m > 0: scores[cat] = m
        if not scores: return "unknown", 0.2
        best = max(scores, key=scores.get)
        return best, round(min(0.5 + scores[best] * 0.15, 0.9), 3)

class MetricClassifier:
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
        for name, thresh, cat, w in self.rules:
            val = metrics.get(name)
            if val is not None and val >= thresh:
                triggered.append((cat, w))
        if not triggered: return "unknown", 0.2
        cat_scores = {}
        for cat, w in triggered:
            if cat not in cat_scores or w > cat_scores[cat]:
                cat_scores[cat] = w
        best = max(cat_scores, key=cat_scores.get)
        return best, round(cat_scores[best], 3)

class LateFusion:
    def __init__(self):
        self.text = TextClassifier()
        self.metric = MetricClassifier()
    def predict(self, text, metrics):
        tc, tconf = self.text.predict(text)
        mc, mconf = self.metric.predict(metrics)
        if tc == mc:
            return tc, round(min((tconf + mconf) / 2 + 0.1, 1.0), 3)
        if tconf >= mconf:
            return tc, round(max(tconf * 0.5 - 0.1, 0.1), 3)
        return mc, round(max(mconf * 0.5 - 0.1, 0.1), 3)

# --- Early Fusion (simplified) ---
class EarlyFusion:
    def __init__(self):
        self.keywords = ["cpu", "memory", "disk", "replication",
                         "lag", "full", "slow", "timeout", "connection"]
        self.text_weights = {
            "cpu": {"performance": 3}, "memory": {"performance": 2},
            "disk": {"storage": 3}, "replication": {"replication": 3},
            "lag": {"replication": 2.5, "performance": 0.5},
            "full": {"storage": 2.5}, "slow": {"performance": 2.5},
            "timeout": {"connectivity": 2.5}, "connection": {"connectivity": 3},
        }
        self.metric_weights = {
            "cpu_percent": ("performance", 85), "disk_percent": ("storage", 85),
            "connections": ("connectivity", 400),
            "replication_lag_seconds": ("replication", 30),
        }

    def predict(self, text, metrics):
        text_lower = text.lower()
        scores = {}
        # Text contributions
        for kw in self.keywords:
            if kw in text_lower:
                for cat, w in self.text_weights.get(kw, {}).items():
                    scores[cat] = scores.get(cat, 0) + w
        # Metric contributions
        for metric, (cat, thresh) in self.metric_weights.items():
            val = metrics.get(metric)
            if val is not None and val >= thresh:
                weight = (val - thresh) / thresh  # higher = more evidence
                scores[cat] = scores.get(cat, 0) + 2 * min(weight, 1.0)
        if not scores:
            return "unknown", 0.2
        total = sum(max(0, v) for v in scores.values())
        best = max(scores, key=scores.get)
        conf = scores[best] / total if total > 0 else 0.2
        return best, round(conf, 3)

# Compare
late = LateFusion()
early = EarlyFusion()

test_cases = [
    # (text, metrics, expected, description)
    ("CPU at 95% queries slow", {"cpu_percent": 95}, "performance",
     "Clear performance - both should get this"),
    ("Disk full on /pgdata", {"disk_percent": 98}, "storage",
     "Clear storage - both should get this"),
    ("Something seems slow", {"cpu_percent": 96}, "performance",
     "Vague text but clear metrics"),
    ("Disk warning", {"cpu_percent": 95, "disk_percent": 60}, "storage",
     "Text says disk, metrics say CPU - tricky!"),
    ("Replication lag on standby", {"cpu_percent": 90, "replication_lag_seconds": 150}, "replication",
     "Text and one metric say replication, CPU also high"),
    ("Server issue", {}, "unknown",
     "No useful text or metrics"),
]

print(f"\n{'Description':<45s} {'Expected':<13s} {'Late':<18s} {'Early':<18s}")
print("-" * 95)

late_correct = 0
early_correct = 0

for text, metrics, expected, desc in test_cases:
    late_cat, late_conf = late.predict(text, metrics)
    early_cat, early_conf = early.predict(text, metrics)

    late_match = "ok" if late_cat == expected else "MISS"
    early_match = "ok" if early_cat == expected else "MISS"

    late_correct += 1 if late_cat == expected else 0
    early_correct += 1 if early_cat == expected else 0

    print(f"{desc:<45s} {expected:<13s} {late_cat} ({late_conf:.0%}) {late_match:<4s}  "
          f"{early_cat} ({early_conf:.0%}) {early_match:<4s}")

n = len(test_cases)
print(f"\nAccuracy:  Late fusion: {late_correct}/{n}  |  Early fusion: {early_correct}/{n}")

print("""
When to use which:

  Late Fusion (two separate models):
    + Easier to debug (know which model said what)
    + Works when one modality is missing
    + Can add/remove modalities easily
    + Each model can be optimized independently
    - Misses cross-modal patterns

  Early Fusion (one combined model):
    + Sees cross-modal patterns ("slow" + high CPU vs "slow" + full disk)
    + One model to maintain
    + Can learn complex interactions
    - Harder to debug
    - Needs ALL features present (or good missing-value handling)

  Production recommendation:
    Start with late fusion (simpler, more debuggable).
    Add early fusion only if late fusion misses cross-modal patterns.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Feature concatenation | Merge all features into one list | Denormalized table with all columns |
| Weight matrix | Score per feature per category | Scoring matrix for diagnosis |
| Cross-modal patterns | Same word, different meaning based on metrics | "slow" + high CPU vs "slow" + full disk |
| Early vs late trade-offs | One model vs two models | One expert vs two specialists |
