# SURVIVE 01: Silent Model Degradation

Your model has been running in production for 3 months. Nobody noticed it went from 92% accuracy to 65%. It missed 12 real incidents last month. The team only discovered the problem during a post-mortem after a major outage.

---

## The Scenario

A DBA deployed an alert classifier 3 months ago. It worked great initially. But the infrastructure team migrated to ARM-based servers, changed the monitoring stack from Nagios to Prometheus, and added 3 new microservices. The model's input data changed, but the model didn't. Nobody was monitoring model accuracy.

---

## Step 1. See the degradation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import accuracy_score, f1_score

np.random.seed(42)

# Simulate: model trained on old data distribution
# Month 0: deploy (model matches production)
# Month 1: small changes (still okay)
# Month 2: monitoring stack change (format drift)
# Month 3: new servers + new services (major drift)

n_per_month = 200

# True labels (incidents happening at constant 15% rate)
def generate_month(drift_factor):
    """Generate production data with increasing drift."""
    y_true = np.zeros(n_per_month, dtype=int)
    n_incidents = int(n_per_month * 0.15)
    y_true[:n_incidents] = 1
    np.random.shuffle(y_true)

    # Model accuracy degrades with drift
    base_accuracy = 0.92
    effective_accuracy = max(0.50, base_accuracy - drift_factor * 0.09)
    # Each drift_factor point reduces accuracy by 9%

    y_pred = y_true.copy()
    n_errors = int(n_per_month * (1 - effective_accuracy))
    error_indices = np.random.choice(n_per_month, n_errors, replace=False)
    y_pred[error_indices] = 1 - y_pred[error_indices]  # flip predictions

    return y_true, y_pred

print("Silent Model Degradation Over 3 Months")
print("=" * 60)
print(f"{'Month':>6s}  {'Accuracy':>9s}  {'F1':>6s}  {'Missed':>7s}  {'Status':>10s}")
print("-" * 45)

months = [
    (0, 0.0, "Deploy"),
    (1, 0.5, "Minor changes"),
    (2, 1.5, "New monitoring"),
    (3, 3.0, "New infra"),
]

for month, drift, event in months:
    y_true, y_pred = generate_month(drift)
    acc = accuracy_score(y_true, y_pred)
    f1 = f1_score(y_true, y_pred, zero_division=0)
    missed = ((y_true == 1) & (y_pred == 0)).sum()
    total_incidents = y_true.sum()

    status = "OK" if acc > 0.85 else "WARNING" if acc > 0.75 else "CRITICAL"
    print(f"{month:>6d}  {acc:>8.1%}  {f1:>5.1%}  {missed:>3d}/{total_incidents:>2d}     {status:>10s}  ({event})")

print()
print("Without monitoring:")
print("  - Month 0-1: nobody checks, everything seems fine")
print("  - Month 2: a few missed alerts, attributed to 'noise'")
print("  - Month 3: major outage, post-mortem reveals model was broken")
print()
print("The model degraded silently because NOBODY WAS WATCHING.")
PYEOF
```

Expected output (yours will differ):

```
Silent Model Degradation Over 3 Months
============================================================
 Month  Accuracy      F1  Missed      Status
---------------------------------------------
     0     92.0%   72.0%    4/30         OK  (Deploy)
     1     87.5%   58.0%    8/30    WARNING  (Minor changes)
     2     78.5%   42.0%   15/30    WARNING  (New monitoring)
     3     65.0%   25.0%   22/30   CRITICAL  (New infra)
```

---

## Step 2. Build the monitoring that would have caught it

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from scipy import stats

np.random.seed(42)

print("""
Prevention: A monitoring system that alerts on model degradation.

Three checks to run daily/weekly:

1. ACCURACY CHECK: Sample predictions, have a human label them
   - Label 50 predictions per week (takes ~30 minutes)
   - If accuracy drops below threshold, alert

2. DATA DRIFT CHECK: Compare input distributions to training
   - No human labeling needed
   - Catches changes before accuracy drops

3. PREDICTION DISTRIBUTION CHECK: Are outputs balanced?
   - If model suddenly predicts one class 80% of the time, something broke
   - No human labeling needed
""")

def monitoring_check(week, accuracy, drift_p_value, pred_balance):
    """Run all three monitoring checks and return alerts."""
    alerts = []

    # Check 1: Accuracy
    if accuracy < 0.80:
        alerts.append(f"CRITICAL: Accuracy dropped to {accuracy:.1%} (threshold: 80%)")
    elif accuracy < 0.85:
        alerts.append(f"WARNING: Accuracy at {accuracy:.1%} (threshold: 85%)")

    # Check 2: Data drift
    if drift_p_value < 0.01:
        alerts.append(f"CRITICAL: Data drift detected (p={drift_p_value:.4f})")
    elif drift_p_value < 0.05:
        alerts.append(f"WARNING: Possible data drift (p={drift_p_value:.4f})")

    # Check 3: Prediction balance
    max_imbalance = max(pred_balance) - min(pred_balance)
    if max_imbalance > 0.30:
        alerts.append(f"CRITICAL: Prediction imbalance ({max_imbalance:.1%} spread)")
    elif max_imbalance > 0.20:
        alerts.append(f"WARNING: Prediction skew ({max_imbalance:.1%} spread)")

    return alerts

# Simulate weekly checks
print("Weekly Monitoring Report")
print("=" * 60)

weeks = [
    (1, 0.91, 0.45, [0.34, 0.26, 0.24, 0.16]),  # Normal
    (4, 0.89, 0.32, [0.32, 0.28, 0.25, 0.15]),  # Normal
    (8, 0.84, 0.04, [0.28, 0.38, 0.22, 0.12]),  # Drift starting
    (10, 0.78, 0.001, [0.20, 0.50, 0.20, 0.10]),  # Drifted
    (12, 0.65, 0.0001, [0.15, 0.60, 0.18, 0.07]),  # Severely drifted
]

for week, acc, drift_p, pred_dist in weeks:
    alerts = monitoring_check(week, acc, drift_p, pred_dist)
    print(f"\nWeek {week:>2d}:")
    print(f"  Sampled accuracy: {acc:.1%}")
    print(f"  Drift p-value:    {drift_p:.4f}")
    print(f"  Pred distribution: {[f'{p:.0%}' for p in pred_dist]}")
    if alerts:
        for alert in alerts:
            print(f"  >>> {alert}")
    else:
        print(f"  Status: All clear")

print()
print("WITH monitoring:")
print("  - Week 8: data drift WARNING caught early")
print("  - Week 10: accuracy and drift alerts triggered")
print("  - Action: retrain model before Week 12 outage")
print()
print("The monitoring system would have caught the degradation")
print("at Week 8 - a full month before the outage at Week 12.")
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| No accuracy monitoring | Model silently degrades | Sample and label 50 predictions/week |
| No drift detection | Input data changes unnoticed | KS test on features weekly |
| No prediction monitoring | Output distribution shifts | Chi-squared test on predictions |
| No alerting thresholds | Problems discovered in post-mortems | Set accuracy, drift, and balance alerts |
