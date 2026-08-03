# Survive 02: Modality Imbalance

Your multi-modal model has been in production for 2 months. It achieves 91% accuracy on your test set. But a deep dive reveals the model completely ignores metrics - it's making every decision based on text alone. The metric pipeline cost $500/month, and it's adding zero value.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'
import random
random.seed(42)

print("""
SCENARIO: Modality Imbalance

Your multi-modal classifier:
  - Input: alert text + server metrics
  - Method: early fusion (combine features, one model)
  - Test accuracy: 91%
  - Production runtime: 2 months

The discovery:
  A new engineer runs an ablation study (remove one modality at a time):
    Text + Metrics: 91% accuracy
    Text ONLY:      90% accuracy   <- almost the same!
    Metrics ONLY:   52% accuracy   <- barely better than random

  The model learned to IGNORE metrics entirely.
  The $500/month Prometheus pipeline adds 1% accuracy.

Why this happened:
  1. Text features are MORE predictive than metric features
  2. During training, the model found text patterns faster
  3. Metric features got drowned out (low weight, eventually zero)
  4. No one checked if BOTH modalities were being used

DBA analogy: creating a multi-column index but the optimizer
only uses the first column. The other columns are dead weight.
  CREATE INDEX idx ON alerts (message_text, cpu_percent, disk_percent);
  -- optimizer only uses message_text, ignores the rest
""")

# Demonstrate the imbalance
print("Ablation Study Results:")
print("=" * 55)

test_data = []
for _ in range(500):
    # Text is highly predictive (correct 90% of the time)
    text_correct = random.random() < 0.90

    # Metrics are weakly predictive (correct 55% of the time)
    metric_correct = random.random() < 0.55

    # The model learned to rely only on text
    # (model_prediction matches text_prediction almost always)
    model_correct = text_correct

    test_data.append({
        "text_correct": text_correct,
        "metric_correct": metric_correct,
        "model_correct": model_correct,
    })

text_only_acc = sum(1 for d in test_data if d["text_correct"]) / len(test_data)
metric_only_acc = sum(1 for d in test_data if d["metric_correct"]) / len(test_data)
model_acc = sum(1 for d in test_data if d["model_correct"]) / len(test_data)

print(f"  Text + Metrics (model):  {model_acc:.1%}")
print(f"  Text only:               {text_only_acc:.1%}")
print(f"  Metrics only:            {metric_only_acc:.1%}")
print(f"  Metric contribution:     {model_acc - text_only_acc:+.1%}")
print(f"  Metric pipeline cost:    $500/month")

# Calculate cost per accuracy point
if model_acc > text_only_acc:
    cost_per_point = 500 / ((model_acc - text_only_acc) * 100)
    print(f"  Cost per accuracy point: ${cost_per_point:.0f}/month")
else:
    print(f"  Cost per accuracy point: infinite (no improvement)")

print("""
The problem isn't just wasted money:
  1. The metric pipeline adds complexity (more things to break)
  2. If metrics break, the model doesn't degrade (it never used them)
  3. You think you have multi-modal defense, but you don't
  4. Cases where ONLY metrics would help are being missed

These are the REAL losses:
  - Alerts where text is vague but metrics are clear
  - "Something seems slow" + cpu=98% -> should be "performance"
  - Without metrics, these get classified as "unknown"
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'
import random
random.seed(42)

print("Investigation: Why Metrics Are Being Ignored")
print("=" * 55)

# Simulate feature weights from a trained model
print("""
Method 1: Check Feature Weights

After training, each feature has a weight (importance).
If metric features all have weights near zero, the model ignores them.
""")

# Simulated weights after training
feature_weights = {
    # Text features - high weights (model relies on these)
    "text_cpu": 2.8,
    "text_disk": 2.6,
    "text_replication": 2.5,
    "text_slow": 2.1,
    "text_full": 2.0,
    "text_connection": 1.9,
    "text_timeout": 1.7,
    "text_lag": 1.5,

    # Metric features - near-zero weights (model ignores these)
    "metric_cpu_percent": 0.05,
    "metric_disk_percent": 0.03,
    "metric_connections": 0.02,
    "metric_replication_lag": 0.01,
    "metric_memory_percent": 0.00,
}

print("  Feature weights (sorted by importance):")
print("  " + "-" * 45)
for name, weight in sorted(feature_weights.items(), key=lambda x: x[1], reverse=True):
    bar = "#" * int(weight * 8)
    label = "TEXT" if name.startswith("text_") else "METRIC"
    flag = " <- DEAD" if weight < 0.1 and name.startswith("metric_") else ""
    print(f"    {name:<30s} {weight:>5.2f} {bar}{flag}")

# Summarize
text_weights = [v for k, v in feature_weights.items() if k.startswith("text_")]
metric_weights = [v for k, v in feature_weights.items() if k.startswith("metric_")]

print(f"\n  Text features avg weight:   {sum(text_weights)/len(text_weights):.2f}")
print(f"  Metric features avg weight: {sum(metric_weights)/len(metric_weights):.3f}")
print(f"  Ratio: text is {sum(text_weights)/max(sum(metric_weights), 0.01):.0f}x more influential")

print("""
Method 2: Feature Correlation Analysis

Why metrics have low weight:
  - Text keywords like "cpu" are perfectly correlated with the "performance" label
  - The metric cpu_percent only adds information when text is vague
  - But vague text is rare (most alerts have clear keywords)
  - So the model learned: "text is enough, ignore metrics"

ROOT CAUSES:
  1. Text features are too predictive (make metrics redundant)
  2. Training didn't force the model to use metrics
  3. No regularization to balance modality weights
  4. No evaluation of per-modality contribution during training
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
import random
random.seed(42)

print("""
FIX: Force the model to use both modalities.

Strategy 1: Modality dropout (randomly hide text during training)
Strategy 2: Separate loss per modality (each must contribute)
Strategy 3: Metric-only test cases (force metric learning)
Strategy 4: Cost-benefit analysis (decide if metrics are worth keeping)
""")

# Strategy 1: Modality Dropout
print("Strategy 1: Modality Dropout")
print("=" * 50)

class ModalityDropoutTrainer:
    """
    During training, randomly DROP one modality.
    This forces the model to learn from each modality independently.

    DBA analogy: like failover testing.
    Randomly kill the primary to force the standby to work.
    If you never test failover, the standby might not work when needed.

    How it works:
      - 60% of training: use both text + metrics (normal)
      - 20% of training: use text only (drop metrics)
      - 20% of training: use metrics only (drop text)

    The model MUST learn to use metrics because sometimes
    text won't be available during training.
    """

    def __init__(self, text_drop_rate=0.2, metric_drop_rate=0.2):
        self.text_drop_rate = text_drop_rate
        self.metric_drop_rate = metric_drop_rate
        self.mode_counts = {"full": 0, "text_only": 0, "metrics_only": 0}

    def prepare_training_batch(self, text_features, metric_features):
        """
        Randomly drop one modality from a training example.
        Returns (text_features, metric_features) with possible zeros.
        """
        roll = random.random()           # random number 0.0 to 1.0

        if roll < self.text_drop_rate:
            # Drop text: zero out text features
            self.mode_counts["metrics_only"] += 1
            return {k: 0.0 for k in text_features}, metric_features

        elif roll < self.text_drop_rate + self.metric_drop_rate:
            # Drop metrics: zero out metric features
            self.mode_counts["text_only"] += 1
            return text_features, {k: 0.0 for k in metric_features}

        else:
            # Use both
            self.mode_counts["full"] += 1
            return text_features, metric_features


trainer = ModalityDropoutTrainer(text_drop_rate=0.2, metric_drop_rate=0.2)

# Simulate 1000 training examples
for _ in range(1000):
    text_f = {"text_cpu": 1.0, "text_slow": 1.0}
    metric_f = {"metric_cpu": 0.95}
    trainer.prepare_training_batch(text_f, metric_f)

print(f"\n  Training distribution over 1000 examples:")
for mode, count in trainer.mode_counts.items():
    pct = count / 1000 * 100
    bar = "#" * int(pct / 2)
    print(f"    {mode:<15s} {count:>4d} ({pct:.0f}%) {bar}")

print("""
  Result: 20% of training forces the model to use metrics only.
  It can't learn to ignore metrics because sometimes text isn't there.
""")


# Strategy 2: Minimum modality contribution
print("Strategy 2: Minimum Modality Contribution")
print("=" * 50)

def check_modality_balance(feature_weights, min_contribution=0.1):
    """
    Check that each modality contributes at least min_contribution
    to the total model weight.

    DBA analogy: like checking that each column in a composite index
    is actually being used. If idx_scan only uses column 1,
    the other columns are wasted.
    """
    text_total = sum(abs(v) for k, v in feature_weights.items() if k.startswith("text_"))
    metric_total = sum(abs(v) for k, v in feature_weights.items() if k.startswith("metric_"))
    total = text_total + metric_total

    if total == 0:
        return False, "no_weights"

    text_pct = text_total / total
    metric_pct = metric_total / total

    issues = []
    if text_pct < min_contribution:
        issues.append(f"text contribution too low: {text_pct:.1%}")
    if metric_pct < min_contribution:
        issues.append(f"metric contribution too low: {metric_pct:.1%}")

    return len(issues) == 0, {
        "text_contribution": round(text_pct, 3),
        "metric_contribution": round(metric_pct, 3),
        "issues": issues,
    }

# Check the broken model
broken_weights = {
    "text_cpu": 2.8, "text_disk": 2.6, "text_slow": 2.1,
    "metric_cpu": 0.05, "metric_disk": 0.03,
}

balanced, info = check_modality_balance(broken_weights, min_contribution=0.1)
print(f"\n  Broken model:")
print(f"    Text contribution:   {info['text_contribution']:.0%}")
print(f"    Metric contribution: {info['metric_contribution']:.0%}")
print(f"    Balanced: {balanced}")
if info['issues']:
    for issue in info['issues']:
        print(f"    Issue: {issue}")

# Check a fixed model
fixed_weights = {
    "text_cpu": 2.0, "text_disk": 1.8, "text_slow": 1.5,
    "metric_cpu": 0.8, "metric_disk": 0.6,
}

balanced, info = check_modality_balance(fixed_weights, min_contribution=0.1)
print(f"\n  Fixed model:")
print(f"    Text contribution:   {info['text_contribution']:.0%}")
print(f"    Metric contribution: {info['metric_contribution']:.0%}")
print(f"    Balanced: {balanced}")


# Strategy 3: Metric-only test cases
print(f"\nStrategy 3: Metric-Only Test Cases")
print("=" * 50)

print("""
  Add test cases where text is deliberately vague
  and ONLY metrics can give the right answer.

  Test cases to add:
    "Server issue"     + cpu=98%    -> must predict "performance"
    "Alert triggered"  + disk=97%   -> must predict "storage"
    "Check server"     + lag=300s   -> must predict "replication"
    "Something wrong"  + conn=490   -> must predict "connectivity"

  If the model fails these, it's not using metrics.
  Like behavioral tests for database features:
    You don't just test overall query speed.
    You test specific scenarios that exercise specific features.
""")

# Strategy 4: Cost-benefit analysis
print(f"Strategy 4: Cost-Benefit Analysis")
print("=" * 50)

def cost_benefit(text_only_acc, full_acc, pipeline_cost_monthly, incidents_per_month, cost_per_incident):
    """
    Should you keep the metric pipeline?

    DBA analogy: should you keep the standby?
    Cost: $X/month for the server
    Benefit: saves $Y per failover event
    Break-even: cost / benefit = how many incidents to justify
    """
    accuracy_improvement = full_acc - text_only_acc
    incidents_prevented = incidents_per_month * accuracy_improvement
    savings_per_month = incidents_prevented * cost_per_incident

    roi = savings_per_month - pipeline_cost_monthly

    return {
        "accuracy_improvement": f"{accuracy_improvement:.1%}",
        "incidents_prevented_monthly": round(incidents_prevented, 1),
        "savings_per_month": f"${savings_per_month:.0f}",
        "pipeline_cost": f"${pipeline_cost_monthly:.0f}",
        "monthly_roi": f"${roi:.0f}",
        "keep_pipeline": roi > 0,
    }

# Before fix
before = cost_benefit(
    text_only_acc=0.90,
    full_acc=0.91,              # only 1% improvement
    pipeline_cost_monthly=500,
    incidents_per_month=100,
    cost_per_incident=200,
)

# After fix (with modality dropout, metrics now contribute more)
after = cost_benefit(
    text_only_acc=0.90,
    full_acc=0.95,              # 5% improvement after fix
    pipeline_cost_monthly=500,
    incidents_per_month=100,
    cost_per_incident=200,
)

print(f"\n  Before fix (metrics adding 1%):")
for k, v in before.items():
    print(f"    {k}: {v}")

print(f"\n  After fix (metrics adding 5%):")
for k, v in after.items():
    print(f"    {k}: {v}")

print("""
Prevention checklist:
  1. Run ablation study monthly (check each modality's contribution)
  2. Use modality dropout during training (force each to contribute)
  3. Add metric-only test cases (ensure metrics can stand alone)
  4. Monitor feature weights (alert if any modality's weight drops to zero)
  5. Track cost/benefit per modality (justify the pipeline cost)
  6. Minimum contribution threshold (block deployment if one modality is dead)
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Modality imbalance | One data type dominates, others wasted | Modality dropout training |
| Dead metric features | Model ignores expensive pipeline | Minimum contribution check |
| No ablation testing | Don't know which modality matters | Monthly ablation studies |
| False sense of multi-modal | Think you have redundancy, you don't | Metric-only test cases |
| Unjustified pipeline cost | Paying for unused data source | Cost-benefit analysis |
