# Build 04: Missing Data and Modality Alignment

Real-world multi-modal data is messy. Metrics might be missing, timestamps don't align, and one data type might dominate. This build handles all of that.

---

## Step 1. Handle missing modalities

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# MISSING MODALITY HANDLING
# Not every alert comes with both text AND metrics.
# Some have text only. Some have metrics only.
# Your model must work with whatever is available.
#
# DBA analogy: LEFT JOIN behavior.
# SELECT * FROM alerts LEFT JOIN metrics USING (alert_id);
# Sometimes metrics is NULL. You still need to return results.
# ============================================================

print("Missing Modality Handling")
print("=" * 50)

class RobustMultiModalClassifier:
    """
    Classifier that works even when data is missing.

    Three operating modes:
    1. Full mode: text + metrics available -> best accuracy
    2. Text-only mode: no metrics -> use text model
    3. Metrics-only mode: no text -> use metric model

    DBA analogy: like a diagnostic script that adapts:
    - If Grafana is down, diagnose from logs only
    - If logs are empty, diagnose from metrics only
    - If both available, use everything
    """

    def __init__(self):
        # Text keyword rules
        self.text_rules = {
            "performance": ["cpu", "slow", "latency", "query"],
            "storage": ["disk", "space", "full", "tablespace", "wal"],
            "replication": ["replication", "lag", "standby"],
            "connectivity": ["connection", "timeout", "refused"],
        }

        # Metric threshold rules
        self.metric_rules = [
            ("cpu_percent", 85, "performance"),
            ("disk_percent", 85, "storage"),
            ("connections", 400, "connectivity"),
            ("replication_lag_seconds", 30, "replication"),
        ]

    def _predict_text(self, text):
        """Predict from text only."""
        text_lower = text.lower()
        scores = {}
        for cat, kws in self.text_rules.items():
            m = sum(1 for kw in kws if kw in text_lower)
            if m > 0:
                scores[cat] = m
        if not scores:
            return "unknown", 0.2
        best = max(scores, key=scores.get)
        conf = min(0.5 + scores[best] * 0.15, 0.85)  # cap at 0.85 (text-only is less sure)
        return best, round(conf, 3)

    def _predict_metrics(self, metrics):
        """Predict from metrics only."""
        triggered = []
        for name, thresh, cat in self.metric_rules:
            val = metrics.get(name)
            if val is not None and val >= thresh:
                severity = min((val - thresh) / thresh, 1.0)
                triggered.append((cat, 0.5 + severity * 0.35))
        if not triggered:
            return "unknown", 0.2
        best_cat = max(triggered, key=lambda x: x[1])
        return best_cat[0], round(min(best_cat[1], 0.85), 3)

    def predict(self, text=None, metrics=None):
        """
        Predict with whatever data is available.
        Returns (category, confidence, mode_used).

        mode_used tells you which path was taken:
          'full' = both text and metrics
          'text_only' = only text available
          'metrics_only' = only metrics available
          'no_data' = nothing available
        """

        has_text = text is not None and text.strip() != ""
        has_metrics = metrics is not None and len(metrics) > 0

        # Case 1: Both available -> full fusion
        if has_text and has_metrics:
            text_cat, text_conf = self._predict_text(text)
            metric_cat, metric_conf = self._predict_metrics(metrics)

            if text_cat == metric_cat:
                # Agreement - boost confidence
                conf = min((text_conf + metric_conf) / 2 + 0.1, 1.0)
                return text_cat, round(conf, 3), "full"
            else:
                # Disagreement - pick higher confidence, reduce
                if text_conf >= metric_conf:
                    return text_cat, round(max(text_conf - 0.1, 0.2), 3), "full"
                else:
                    return metric_cat, round(max(metric_conf - 0.1, 0.2), 3), "full"

        # Case 2: Text only
        if has_text:
            cat, conf = self._predict_text(text)
            return cat, conf, "text_only"

        # Case 3: Metrics only
        if has_metrics:
            cat, conf = self._predict_metrics(metrics)
            return cat, conf, "metrics_only"

        # Case 4: No data
        return "unknown", 0.0, "no_data"


# Test all four modes
model = RobustMultiModalClassifier()

test_cases = [
    # (text, metrics, description)
    ("CPU at 95% queries slow", {"cpu_percent": 95}, "Full: text + metrics"),
    ("Disk full on /pgdata", None, "Text only: no metrics"),
    (None, {"cpu_percent": 96, "disk_percent": 40}, "Metrics only: no text"),
    ("", {}, "No data: empty text + empty metrics"),
    ("Connection timeout", {"connections": 450}, "Full: connectivity"),
    ("Something happened", None, "Text only: vague text"),
    (None, {"cpu_percent": 50, "disk_percent": 40}, "Metrics only: everything normal"),
]

print("\nHandling Missing Modalities:")
print("-" * 70)
print(f"{'Description':<40s} {'Category':<15s} {'Conf':>5s} {'Mode':<12s}")
print("-" * 70)

for text, metrics, desc in test_cases:
    cat, conf, mode = model.predict(text, metrics)
    print(f"{desc:<40s} {cat:<15s} {conf:>5.0%} {mode:<12s}")

print("""
Key design decisions:
  1. Cap text-only confidence at 85% (less data = less certainty)
  2. Cap metric-only confidence at 85% (same reason)
  3. Full mode can reach 100% (both sources confirm)
  4. "no_data" always returns unknown at 0% confidence
""")
PYEOF
```

---

## Step 2. Time alignment

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime, timedelta

# ============================================================
# TIME ALIGNMENT
# Text alerts arrive at one timestamp.
# Metrics are sampled at regular intervals (e.g., every 60 seconds).
# To combine them, you need to align the timestamps.
#
# DBA analogy: joining two tables with different granularity.
# Alerts have exact timestamps.
# Metrics have one row per minute.
# You need to match each alert to the closest metric window.
#
# SELECT a.*, m.*
# FROM alerts a
# JOIN metrics m ON m.ts = date_trunc('minute', a.ts);
# ============================================================

print("Time Alignment")
print("=" * 50)

class TimeAligner:
    """
    Align text alerts with metric snapshots by timestamp.

    DBA analogy: like date_trunc() or a time-based JOIN.
    Alert at 14:03:27 matches metrics from 14:03:00 window.
    """

    def __init__(self, window_seconds=60):
        """
        window_seconds: size of each metric window.
        60 = one metric snapshot per minute.
        """
        self.window_seconds = window_seconds

    def snap_to_window(self, timestamp):
        """
        Round a timestamp DOWN to the nearest window boundary.

        If window = 60 seconds:
          14:03:27 -> 14:03:00
          14:03:59 -> 14:03:00
          14:04:01 -> 14:04:00

        DBA analogy: date_trunc('minute', timestamp)
        """
        # Convert to seconds since epoch, round down, convert back
        epoch_seconds = timestamp.timestamp()     # float: seconds since 1970
        window_start = int(epoch_seconds // self.window_seconds) * self.window_seconds
        return datetime.fromtimestamp(window_start)

    def find_closest_metric(self, alert_time, metric_snapshots):
        """
        Find the metric snapshot closest to the alert time.

        metric_snapshots: list of (timestamp, metrics_dict)
        Returns the closest metrics_dict or None if too far away.

        DBA analogy: LATERAL JOIN to find the nearest row.
        """
        alert_window = self.snap_to_window(alert_time)

        best_match = None
        best_distance = float('inf')     # start with infinity

        for metric_time, metrics in metric_snapshots:
            # Distance in seconds between alert window and metric window
            distance = abs((alert_window - metric_time).total_seconds())

            if distance < best_distance:
                best_distance = distance
                best_match = metrics

        # Only return if within 5 minutes (300 seconds)
        # Metrics older than 5 minutes are stale
        if best_distance <= 300:
            return best_match, best_distance
        else:
            return None, best_distance

    def align_alerts_with_metrics(self, alerts, metric_snapshots):
        """
        Match each alert to its nearest metric snapshot.

        alerts: list of (timestamp, text)
        metric_snapshots: list of (timestamp, metrics_dict)
        Returns list of (text, metrics_or_None, distance_seconds)
        """
        results = []
        for alert_time, alert_text in alerts:
            metrics, distance = self.find_closest_metric(alert_time, metric_snapshots)
            results.append({
                "text": alert_text,
                "alert_time": alert_time,
                "metrics": metrics,
                "metric_distance_seconds": round(distance, 1),
                "has_metrics": metrics is not None,
            })
        return results


# Simulate: alerts arrive at exact times, metrics every 60 seconds
now = datetime.now()

# Metric snapshots every 60 seconds for the last 10 minutes
metric_snapshots = []
for i in range(10):
    ts = now - timedelta(minutes=i)
    ts = ts.replace(second=0, microsecond=0)  # snap to minute boundary
    metrics = {
        "cpu_percent": 50 + i * 5,       # CPU climbing over time
        "disk_percent": 80 + i,           # disk slowly filling
    }
    metric_snapshots.append((ts, metrics))

# Sort oldest first
metric_snapshots.sort(key=lambda x: x[0])

# Alerts arrive at random-ish times
alerts = [
    (now - timedelta(minutes=2, seconds=27), "CPU at 95%"),
    (now - timedelta(minutes=5, seconds=3), "Disk growing fast"),
    (now - timedelta(seconds=15), "Query timeout"),
    (now - timedelta(minutes=20), "Old alert, no matching metrics"),
]

aligner = TimeAligner(window_seconds=60)

print("\nMetric snapshots (last 10 minutes):")
for ts, m in metric_snapshots[-5:]:    # show last 5
    print(f"  {ts.strftime('%H:%M:%S')} -> cpu={m['cpu_percent']}%, disk={m['disk_percent']}%")

print("\nAligning alerts with metrics:")
print("-" * 65)

aligned = aligner.align_alerts_with_metrics(alerts, metric_snapshots)

for item in aligned:
    text = item["text"]
    has_m = item["has_metrics"]
    dist = item["metric_distance_seconds"]

    if has_m:
        m = item["metrics"]
        print(f"  '{text}' at {item['alert_time'].strftime('%H:%M:%S')}")
        print(f"    Matched metrics ({dist:.0f}s away): cpu={m['cpu_percent']}%, disk={m['disk_percent']}%")
    else:
        print(f"  '{text}' at {item['alert_time'].strftime('%H:%M:%S')}")
        print(f"    NO MATCH: closest metric is {dist:.0f}s away (>300s limit)")
    print()

print("""
Time alignment rules:
  1. Snap alert timestamp to nearest metric window (like date_trunc)
  2. Find the metric snapshot closest to that window
  3. If closest metric is > 5 minutes old, treat as missing
  4. Stale metrics are worse than no metrics (misleading data)
""")
PYEOF
```

---

## Step 3. Modality weighting

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# MODALITY WEIGHTING
# Automatically adjust how much to trust each data type
# based on how useful it has been historically.
#
# DBA analogy: if your metrics are noisy (frequent false alarms),
# you learn to trust the log messages more. The model should
# learn the same thing automatically.
# ============================================================

print("Dynamic Modality Weighting")
print("=" * 50)

class DynamicWeightedFusion:
    """
    Automatically adjust text vs metric weights based on
    how accurate each model has been recently.

    DBA analogy: you trust the monitoring tool that has been
    right most often. If Grafana has been giving false alarms
    but logs have been accurate, you weight logs higher.
    """

    def __init__(self, initial_text_weight=0.5, learning_rate=0.1):
        """
        initial_text_weight: starting trust in text model (0 to 1).
                             metric weight = 1 - text_weight.
        learning_rate: how fast weights adjust (0.1 = cautious, 0.5 = aggressive).
        """
        self.text_weight = initial_text_weight
        self.metric_weight = 1.0 - initial_text_weight
        self.learning_rate = learning_rate

        # Track accuracy per model
        self.text_correct = 0          # how many times text model was right
        self.text_total = 0            # total predictions by text model
        self.metric_correct = 0
        self.metric_total = 0

        # History for display
        self.weight_history = [(self.text_weight, self.metric_weight)]

    def _text_predict(self, text):
        """Simple text classifier."""
        text_lower = text.lower()
        rules = {
            "performance": ["cpu", "slow", "latency", "query"],
            "storage": ["disk", "space", "full", "wal"],
            "replication": ["replication", "lag", "standby"],
            "connectivity": ["connection", "timeout"],
        }
        for cat, kws in rules.items():
            if any(kw in text_lower for kw in kws):
                return cat, 0.8
        return "unknown", 0.2

    def _metric_predict(self, metrics):
        """Simple metric classifier."""
        rules = [
            ("cpu_percent", 85, "performance"),
            ("disk_percent", 85, "storage"),
            ("connections", 400, "connectivity"),
            ("replication_lag_seconds", 30, "replication"),
        ]
        for name, thresh, cat in rules:
            val = metrics.get(name)
            if val is not None and val >= thresh:
                return cat, 0.8
        return "unknown", 0.2

    def predict(self, text, metrics):
        """Predict using current weights."""
        text_cat, text_conf = self._text_predict(text)
        metric_cat, metric_conf = self._metric_predict(metrics)

        # Weighted scores
        text_score = text_conf * self.text_weight
        metric_score = metric_conf * self.metric_weight

        if text_score >= metric_score:
            return text_cat, round(text_score + metric_score * 0.5, 3)
        else:
            return metric_cat, round(metric_score + text_score * 0.5, 3)

    def update_weights(self, text, metrics, actual_category):
        """
        After learning the true answer, adjust weights.

        If text model was right and metric model was wrong,
        increase text weight (and decrease metric weight).

        DBA analogy: after an incident, you note which tool
        gave the right diagnosis. Next time, you trust it more.
        """
        text_cat, _ = self._text_predict(text)
        metric_cat, _ = self._metric_predict(metrics)

        # Track accuracy
        self.text_total += 1
        self.metric_total += 1
        if text_cat == actual_category:
            self.text_correct += 1
        if metric_cat == actual_category:
            self.metric_correct += 1

        # Adjust weights based on who was right
        text_right = (text_cat == actual_category)
        metric_right = (metric_cat == actual_category)

        if text_right and not metric_right:
            # Text was right, metrics wrong -> trust text more
            self.text_weight = min(0.9, self.text_weight + self.learning_rate)
        elif metric_right and not text_right:
            # Metrics were right, text wrong -> trust metrics more
            self.text_weight = max(0.1, self.text_weight - self.learning_rate)
        # If both right or both wrong, no change

        self.metric_weight = 1.0 - self.text_weight
        self.weight_history.append((
            round(self.text_weight, 3),
            round(self.metric_weight, 3)
        ))


# Simulate a scenario where metrics become unreliable
model = DynamicWeightedFusion(initial_text_weight=0.5, learning_rate=0.05)

# Training data: first batch - both models work well
training_batch_1 = [
    ("CPU at 95%", {"cpu_percent": 95}, "performance"),
    ("Disk full", {"disk_percent": 98}, "storage"),
    ("Replication lag", {"replication_lag_seconds": 120}, "replication"),
]

# Second batch: metrics are wrong (monitoring misconfigured)
training_batch_2 = [
    ("CPU at 95%", {"cpu_percent": 30}, "performance"),      # metric wrong
    ("Disk full", {"disk_percent": 20}, "storage"),           # metric wrong
    ("Replication lag", {"replication_lag_seconds": 5}, "replication"), # metric wrong
    ("Connection timeout", {"cpu_percent": 95}, "connectivity"),  # metric wrong
    ("Query very slow", {"disk_percent": 95}, "performance"),     # metric wrong
]

print("\nPhase 1: Both models accurate")
print("-" * 50)
for text, metrics, actual in training_batch_1:
    pred_cat, pred_conf = model.predict(text, metrics)
    model.update_weights(text, metrics, actual)
    print(f"  Text={model.text_weight:.2f} Metric={model.metric_weight:.2f} "
          f"| Predicted: {pred_cat:<15s} Actual: {actual}")

print(f"\nPhase 2: Metrics become unreliable")
print("-" * 50)
for text, metrics, actual in training_batch_2:
    pred_cat, pred_conf = model.predict(text, metrics)
    model.update_weights(text, metrics, actual)
    print(f"  Text={model.text_weight:.2f} Metric={model.metric_weight:.2f} "
          f"| Predicted: {pred_cat:<15s} Actual: {actual}")

# Show final state
text_acc = model.text_correct / model.text_total * 100 if model.text_total > 0 else 0
metric_acc = model.metric_correct / model.metric_total * 100 if model.metric_total > 0 else 0

print(f"\nFinal Results:")
print(f"  Text accuracy:   {model.text_correct}/{model.text_total} ({text_acc:.0f}%)")
print(f"  Metric accuracy: {model.metric_correct}/{model.metric_total} ({metric_acc:.0f}%)")
print(f"  Final weights:   text={model.text_weight:.2f}, metric={model.metric_weight:.2f}")

print(f"\nWeight evolution:")
for i, (tw, mw) in enumerate(model.weight_history):
    bar_t = "#" * int(tw * 20)
    bar_m = "#" * int(mw * 20)
    print(f"  Step {i:>2d}: text={tw:.2f} {bar_t:<20s} metric={mw:.2f} {bar_m}")

print("""
What happened:
  1. Started at 50/50 weights (equal trust)
  2. In Phase 1, both models were right, weights stayed balanced
  3. In Phase 2, metrics were wrong repeatedly
  4. Model automatically shifted trust toward text
  5. This is ADAPTIVE - if metrics improve, weights shift back

DBA parallel: this is like learning which monitoring tool to trust.
After Grafana gives false alarms 5 times in a row, you start
checking the logs first. The model learns the same way.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Missing modality handling | Work with partial data | LEFT JOIN - handle NULLs |
| Confidence capping | Less data = less certainty | One source = less sure |
| Time alignment | Match alerts to metrics by timestamp | date_trunc + time-based JOIN |
| Staleness check | Reject old metrics | Don't use yesterday's metrics |
| Dynamic weighting | Auto-adjust trust per modality | Learn which monitoring tool to trust |
| Weight history | Track how trust shifts over time | Audit trail of decision changes |
