# Build 04: Monitoring and Drift Detection

Your model works great on day 1. But the world changes - new query patterns, different alert formats, infrastructure upgrades. Without monitoring, your model silently degrades. This guide shows you how to detect drift before it causes problems.

---

## Step 1. What is model drift?

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Model Drift: Your model gets worse over time because the real world
changed but the model didn't.

Two types of drift:

1. DATA DRIFT (input distribution changes)
   - Training: CPU values ranged 20-90%
   - Production: new servers have CPUs running at 5-15% (ARM, efficient)
   - The model has never seen these low values and predicts poorly

2. CONCEPT DRIFT (the relationship between input and output changes)
   - Training: CPU > 80% = incident
   - Reality changed: after hardware upgrade, CPU > 80% is normal
   - The model's rule is now wrong

DBA analogy:
  DATA DRIFT = your table statistics are stale (ANALYZE hasn't run)
    - The planner uses old row counts and makes bad plans
    - Fix: run ANALYZE (retrain the model)

  CONCEPT DRIFT = your queries changed but indexes didn't
    - Old indexes don't help new query patterns
    - Fix: create new indexes (retrain on new patterns)
""")
PYEOF
```

---

## Step 2. Detect data drift

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from scipy import stats

np.random.seed(42)

# Training data distribution (what the model learned from)
train_cpu = np.random.normal(60, 15, 1000)     # mean=60%, std=15%
train_connections = np.random.normal(150, 40, 1000)  # mean=150, std=40

# Production data - Week 1 (similar to training)
prod_week1_cpu = np.random.normal(62, 16, 200)  # slightly different, normal
prod_week1_conn = np.random.normal(155, 42, 200)

# Production data - Week 4 (DRIFTED)
prod_week4_cpu = np.random.normal(45, 20, 200)  # shifted DOWN (new efficient servers)
prod_week4_conn = np.random.normal(300, 60, 200)  # shifted UP (more traffic)

def detect_drift(train_data, prod_data, feature_name, threshold=0.05):
    """Detect if production data differs from training data using KS test."""
    # Kolmogorov-Smirnov test: compares two distributions
    # Returns: statistic (max difference between distributions) and p-value
    statistic, p_value = stats.ks_2samp(train_data, prod_data)
    # ks_2samp = two-sample KS test
    # Small p-value = distributions ARE different (drift detected)

    drifted = p_value < threshold
    status = "DRIFT DETECTED" if drifted else "OK"

    print(f"  {feature_name:>15s}:  "
          f"train mean={train_data.mean():.1f}, "
          f"prod mean={prod_data.mean():.1f}, "
          f"KS stat={statistic:.3f}, "
          f"p={p_value:.4f}  [{status}]")
    return drifted

print("Data Drift Detection (KS Test)")
print("=" * 70)

print("\nWeek 1 (production similar to training):")
d1 = detect_drift(train_cpu, prod_week1_cpu, "CPU %")
d2 = detect_drift(train_connections, prod_week1_conn, "Connections")
if not d1 and not d2:
    print("  -> No drift. Model inputs look normal.")

print("\nWeek 4 (production has drifted):")
d3 = detect_drift(train_cpu, prod_week4_cpu, "CPU %")
d4 = detect_drift(train_connections, prod_week4_conn, "Connections")
if d3 or d4:
    print("  -> DRIFT DETECTED! Consider retraining the model.")
    print("  -> CPU values shifted lower (new hardware?)")
    print("  -> Connection counts shifted higher (more traffic?)")

print()
print("Run drift checks daily/weekly on your production data")
print("Alert when p-value drops below 0.05 for any feature")
PYEOF
```

Expected output (yours will differ):

```
Week 1 (production similar to training):
              CPU %:  train mean=60.0, prod mean=62.0, KS stat=0.067, p=0.7234  [OK]
        Connections:  train mean=150.0, prod mean=155.0, KS stat=0.072, p=0.6543  [OK]
  -> No drift. Model inputs look normal.

Week 4 (production has drifted):
              CPU %:  train mean=60.0, prod mean=45.0, KS stat=0.325, p=0.0001  [DRIFT DETECTED]
        Connections:  train mean=150.0, prod mean=300.0, KS stat=0.891, p=0.0000  [DRIFT DETECTED]
```

---

## Step 3. Detect prediction drift

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from collections import Counter

np.random.seed(42)

print("""
Prediction Drift: The model's outputs change even if accuracy is unknown.

You may not have ground truth labels in production (you don't know
if the model was right until an incident actually happens). But you
CAN monitor the distribution of predictions.

If the model suddenly predicts "storage" for 80% of alerts
(when it used to predict it for 20%), something changed.
""")

# Simulated prediction distributions
# Training: balanced predictions across categories
categories = ["performance", "storage", "replication", "security"]
train_preds = np.random.choice(categories, 1000, p=[0.35, 0.25, 0.25, 0.15])

# Production Week 1: similar to training
prod_w1 = np.random.choice(categories, 200, p=[0.33, 0.27, 0.24, 0.16])

# Production Week 4: drifted (model predicts storage too much)
prod_w4 = np.random.choice(categories, 200, p=[0.15, 0.55, 0.20, 0.10])

def prediction_distribution(preds, name):
    """Show the distribution of predictions."""
    counts = Counter(preds)
    total = len(preds)
    print(f"  {name}:")
    for cat in categories:
        count = counts.get(cat, 0)
        pct = count / total
        bar = "#" * int(pct * 40)
        print(f"    {cat:>15s}: {pct:>5.1%}  {bar}")

print("Prediction Distribution Monitoring")
print("=" * 55)

prediction_distribution(train_preds, "Training baseline")
print()
prediction_distribution(prod_w1, "Production Week 1")
print()
prediction_distribution(prod_w4, "Production Week 4 (DRIFTED)")

print()

# Detect drift using chi-squared test
from scipy.stats import chi2_contingency

def check_prediction_drift(baseline_preds, current_preds, categories):
    """Check if prediction distribution has drifted."""
    baseline_counts = Counter(baseline_preds)
    current_counts = Counter(current_preds)

    # Build contingency table
    observed = np.array([[baseline_counts.get(c, 0) for c in categories],
                         [current_counts.get(c, 0) for c in categories]])
    # 2 x 4 table: [baseline_row, current_row] x [4 categories]

    chi2, p_value, dof, expected = chi2_contingency(observed)
    # chi2_contingency: tests if two distributions are independent
    # Small p-value = distributions ARE different

    return p_value

p_w1 = check_prediction_drift(train_preds, prod_w1, categories)
p_w4 = check_prediction_drift(train_preds, prod_w4, categories)

print(f"Drift test p-values:")
print(f"  Week 1: p={p_w1:.4f}  {'DRIFT' if p_w1 < 0.05 else 'OK'}")
print(f"  Week 4: p={p_w4:.4f}  {'DRIFT' if p_w4 < 0.05 else 'OK'}")
print()
print("When prediction drift is detected:")
print("  1. Check if input data has drifted (Step 2)")
print("  2. Check recent accuracy on a sample with labels")
print("  3. If accuracy dropped, retrain the model")
print("  4. If accuracy is fine, the world changed - update your expectations")
PYEOF
```

---

## Step 4. Build a monitoring dashboard (text-based)

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from scipy import stats
from collections import Counter
from datetime import datetime, timedelta

np.random.seed(42)

print("=" * 60)
print("  AI MODEL MONITORING DASHBOARD")
print(f"  Report generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
print("=" * 60)

# Simulate monitoring data
categories = ["performance", "storage", "replication", "security"]

# Training baseline
train_cpu_mean, train_cpu_std = 60, 15
train_conn_mean, train_conn_std = 150, 40
train_pred_dist = [0.35, 0.25, 0.25, 0.15]

# Current production (simulated)
prod_cpu = np.random.normal(52, 18, 200)
prod_conn = np.random.normal(180, 45, 200)
prod_preds = np.random.choice(categories, 200, p=[0.30, 0.35, 0.22, 0.13])
latencies_ms = np.random.lognormal(3, 0.5, 200)  # inference latency

print()
print("[1] MODEL PERFORMANCE")
print("-" * 40)
# In production, you'd sample and label some predictions
sample_accuracy = 0.87
print(f"  Accuracy (sampled):  {sample_accuracy:.1%}")
print(f"  Status:              {'OK' if sample_accuracy > 0.80 else 'DEGRADED'}")

print()
print("[2] DATA DRIFT")
print("-" * 40)

features = [
    ("CPU %", np.random.normal(train_cpu_mean, train_cpu_std, 1000), prod_cpu),
    ("Connections", np.random.normal(train_conn_mean, train_conn_std, 1000), prod_conn),
]

any_drift = False
for name, train_data, prod_data in features:
    stat, p = stats.ks_2samp(train_data, prod_data)
    drifted = p < 0.05
    if drifted:
        any_drift = True
    status = "DRIFT" if drifted else "OK"
    print(f"  {name:>15s}:  p={p:.4f}  [{status}]")

print(f"  Overall:            {'ACTION NEEDED' if any_drift else 'All clear'}")

print()
print("[3] PREDICTION DRIFT")
print("-" * 40)

pred_counts = Counter(prod_preds)
total = len(prod_preds)
for i, cat in enumerate(categories):
    current_pct = pred_counts.get(cat, 0) / total
    baseline_pct = train_pred_dist[i]
    change = current_pct - baseline_pct
    flag = " !!!" if abs(change) > 0.05 else ""
    print(f"  {cat:>15s}:  {current_pct:>5.1%} (baseline: {baseline_pct:>5.1%}, "
          f"change: {change:>+5.1%}){flag}")

print()
print("[4] INFERENCE HEALTH")
print("-" * 40)
print(f"  Predictions today:   {len(prod_preds)}")
print(f"  Avg latency:         {latencies_ms.mean():.0f}ms")
print(f"  P95 latency:         {np.percentile(latencies_ms, 95):.0f}ms")
print(f"  P99 latency:         {np.percentile(latencies_ms, 99):.0f}ms")
print(f"  Errors:              0")
print(f"  Status:              {'OK' if np.percentile(latencies_ms, 99) < 200 else 'SLOW'}")

print()
print("[5] RECOMMENDATIONS")
print("-" * 40)
if any_drift:
    print("  - Data drift detected. Review feature distributions.")
    print("  - Consider retraining if accuracy has dropped.")
if sample_accuracy < 0.85:
    print("  - Accuracy below 85%. Investigate recent prediction errors.")
if np.percentile(latencies_ms, 99) > 200:
    print("  - P99 latency above 200ms. Check model serving infrastructure.")
if not any_drift and sample_accuracy >= 0.85:
    print("  - All systems nominal. Next review in 7 days.")

print()
print("=" * 60)
PYEOF
```

---

## What You Learned

| Monitoring Area | What to Track | Alert When |
|----------------|--------------|------------|
| Data drift | Input feature distributions (KS test) | p < 0.05 on any feature |
| Prediction drift | Output class distribution (chi-squared) | Distribution shifts > 5% |
| Accuracy | Sampled prediction correctness | Accuracy drops below threshold |
| Latency | P50, P95, P99 inference time | P99 exceeds SLA |
| Error rate | Failed predictions, exceptions | Any non-zero error rate |
