# SURVIVE 02: Misleading Metrics

Your model reports 97% accuracy. Management approves production deployment. In production, it misses every critical alert. The 97% accuracy was real - but meaningless. The metric was correct; the interpretation was wrong.

---

## The Scenario

A DBA trained an incident detection model on a dataset where 97% of servers are healthy. The model learned to always predict "healthy" and achieved 97% accuracy. Nobody checked precision or recall before deploying.

---

## Step 1. See the problem

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
from sklearn.metrics import classification_report

np.random.seed(42)

# Dataset: 1000 servers, 3% incident rate (highly imbalanced)
n = 1000
y_true = np.zeros(n, dtype=int)
y_true[:30] = 1  # only 30 incidents out of 1000
np.random.shuffle(y_true)

# Model A: "Smart" model that always predicts healthy
y_pred_always_healthy = np.zeros(n, dtype=int)

# Model B: Actual model (catches 25/30 incidents, 50 false alarms)
y_pred_actual = y_true.copy()
incidents = np.where(y_true == 1)[0]
y_pred_actual[incidents[:5]] = 0  # miss 5 incidents
healthy = np.where(y_true == 0)[0]
y_pred_actual[healthy[:50]] = 1   # 50 false alarms

print("Two Models, Same Dataset (3% incident rate)")
print("=" * 70)
print()

# Model A metrics
acc_a = accuracy_score(y_true, y_pred_always_healthy)
print(f"Model A: Always predicts 'healthy'")
print(f"  Accuracy: {acc_a:.1%}  <-- looks great!")
print(f"  Incidents caught: 0/30")
print(f"  This model would be approved based on accuracy alone.")
print()

# Model B metrics
acc_b = accuracy_score(y_true, y_pred_actual)
prec_b = precision_score(y_true, y_pred_actual)
rec_b = recall_score(y_true, y_pred_actual)
f1_b = f1_score(y_true, y_pred_actual)
print(f"Model B: Actual useful model")
print(f"  Accuracy: {acc_b:.1%}  <-- looks worse than Model A!")
print(f"  Incidents caught: 25/30")
print(f"  Precision: {prec_b:.1%}")
print(f"  Recall: {rec_b:.1%}")
print(f"  F1: {f1_b:.1%}")
print()

print("The ACCURACY TRAP:")
print(f"  Model A: {acc_a:.1%} accuracy, catches 0 incidents (USELESS)")
print(f"  Model B: {acc_b:.1%} accuracy, catches 25 incidents (USEFUL)")
print()
print("If you only report accuracy, Model A looks better.")
print("This is why accuracy is DANGEROUS for imbalanced data.")
print()

# Full classification report shows the truth
print("Full Classification Report (Model B):")
print(classification_report(y_true, y_pred_actual,
                           target_names=['Healthy', 'Incident']))
PYEOF
```

Expected output (yours will differ):

```
Model A: Always predicts 'healthy'
  Accuracy: 97.0%  <-- looks great!
  Incidents caught: 0/30

Model B: Actual useful model
  Accuracy: 94.5%  <-- looks worse than Model A!
  Incidents caught: 25/30
  Precision: 33.3%
  Recall: 83.3%
  F1: 47.6%
```

---

## Step 2. The metrics that matter

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Metric Selection Guide for DBAs:

NEVER USE ACCURACY ALONE for imbalanced data.

Instead, use this checklist:

1. FOR ALERT SYSTEMS (catching incidents):
   Primary metric: RECALL (sensitivity)
   "Of all real incidents, how many did we catch?"
   Target: > 90% (missing incidents is expensive)

2. FOR AUTOMATED ACTIONS (auto-restart, auto-failover):
   Primary metric: PRECISION
   "Of all times we took action, how many were needed?"
   Target: > 95% (false actions are dangerous)

3. FOR GENERAL CLASSIFICATION (alert routing):
   Primary metric: F1 SCORE
   "Balance between precision and recall"
   Target: > 80% per class

4. FOR MODEL COMPARISON:
   Use: AUC-ROC
   "Overall ranking quality, independent of threshold"
   Higher is better

5. FOR PRODUCTION MONITORING:
   Use: Per-class F1 scores
   "Each category should perform well, not just overall"
   Alert when any class F1 drops below 70%

ALWAYS REPORT:
  - Per-class metrics (not just overall)
  - The confusion matrix (shows exactly where errors happen)
  - The class distribution (so readers know if data is imbalanced)

NEVER REPORT:
  - Accuracy alone (misleading for imbalanced data)
  - Only overall metrics (hides per-class failures)
  - Metrics without confidence intervals (could be random)
""")
PYEOF
```

---

## Step 3. Fix the evaluation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import classification_report, confusion_matrix

np.random.seed(42)

n = 1000
y_true = np.zeros(n, dtype=int)
y_true[:30] = 1
np.random.shuffle(y_true)

# Good model with threshold tuning
probabilities = np.random.beta(2, 8, n)
probabilities[y_true == 1] = np.random.beta(5, 2, 30)
probabilities = np.clip(probabilities, 0, 1)

print("Proper Evaluation Report")
print("=" * 60)
print()

# 1. Dataset info
print("[1] Dataset Information")
print(f"  Total samples: {n}")
print(f"  Healthy: {(y_true == 0).sum()} ({(y_true == 0).mean():.1%})")
print(f"  Incident: {(y_true == 1).sum()} ({(y_true == 1).mean():.1%})")
print(f"  Class imbalance: {(y_true == 0).sum() / (y_true == 1).sum():.0f}:1")
print()

# 2. Find best threshold for recall > 0.90
print("[2] Threshold Selection (target: recall > 90%)")
best_threshold = 0.5
best_f1 = 0

for t in np.arange(0.1, 0.9, 0.05):
    y_pred = (probabilities > t).astype(int)
    recall = (y_pred[y_true == 1] == 1).mean()
    if recall >= 0.90:
        tp = ((y_pred == 1) & (y_true == 1)).sum()
        fp = ((y_pred == 1) & (y_true == 0)).sum()
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
        if f1 > best_f1:
            best_f1 = f1
            best_threshold = t

y_pred = (probabilities > best_threshold).astype(int)
print(f"  Selected threshold: {best_threshold:.2f}")
print(f"  (Best F1 with recall >= 90%)")
print()

# 3. Full metrics
print("[3] Classification Report")
print(classification_report(y_true, y_pred, target_names=['Healthy', 'Incident']))

# 4. Confusion matrix
cm = confusion_matrix(y_true, y_pred)
print("[4] Confusion Matrix")
print(f"  {'':>15s}  {'Pred Healthy':>13s}  {'Pred Incident':>14s}")
print(f"  {'True Healthy':>15s}  {cm[0][0]:>13d}  {cm[0][1]:>14d}")
print(f"  {'True Incident':>15s}  {cm[1][0]:>13d}  {cm[1][1]:>14d}")
print()

# 5. Key numbers for management
missed = cm[1][0]
false_alarms = cm[0][1]
caught = cm[1][1]
total_incidents = y_true.sum()

print("[5] Summary for Management")
print(f"  Incidents caught:   {caught}/{total_incidents} ({caught/total_incidents:.1%})")
print(f"  Incidents missed:   {missed}/{total_incidents}")
print(f"  False alarms:       {false_alarms}/day (estimated)")
print(f"  Overall accuracy:   {(y_pred == y_true).mean():.1%}")
print(f"  NOTE: Accuracy includes 97% easy healthy cases")
print()
print("This report tells the full story. Accuracy alone would be misleading.")
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Report only accuracy | Model looks good but catches nothing | Always report precision, recall, F1 per class |
| Ignore class imbalance | High accuracy = useless model | Check class distribution first |
| No per-class metrics | One category fails silently | Print classification_report for every class |
| No confusion matrix | Don't know which errors occur | Always check the confusion matrix |
| No threshold tuning | Default 0.5 may not be optimal | Tune threshold for your priority (recall vs precision) |
