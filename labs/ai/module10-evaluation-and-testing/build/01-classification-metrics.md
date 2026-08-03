# Build 01: Classification Metrics Deep Dive

Accuracy is not enough. This guide shows you every metric that matters for classification models, when to use each one, and how misleading accuracy can be.

---

## Step 1. Why accuracy lies

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

np.random.seed(42)

print("""
The Accuracy Trap:

Your database has 1000 servers:
  - 950 healthy (95%)
  - 50 with incidents (5%)

A model that ALWAYS predicts "healthy" gets 95% accuracy.
But it catches ZERO incidents. That's useless.

This is why accuracy alone is dangerous for imbalanced data.
""")

# Simulate: 1000 servers, 5% incident rate
n = 1000
y_true = np.zeros(n, dtype=int)     # all zeros (healthy)
y_true[:50] = 1                      # first 50 are incidents
np.random.shuffle(y_true)            # mix them up

# Model A: always predicts "healthy" (useless but 95% accurate)
y_pred_always_healthy = np.zeros(n, dtype=int)

# Model B: catches incidents but has some false alarms
y_pred_model_b = y_true.copy()
# Simulate: misses 10 incidents (false negatives)
incident_indices = np.where(y_true == 1)[0]
# np.where returns indices where condition is True
y_pred_model_b[incident_indices[:10]] = 0  # miss 10 incidents
# Add 30 false alarms
healthy_indices = np.where(y_true == 0)[0]
y_pred_model_b[healthy_indices[:30]] = 1   # 30 false alarms

print(f"{'Model':25s}  {'Accuracy':>9s}  {'Incidents Found':>16s}")
print("-" * 55)

acc_a = accuracy_score(y_true, y_pred_always_healthy)
caught_a = (y_pred_always_healthy[y_true == 1] == 1).sum()
print(f"{'Always predicts healthy':25s}  {acc_a:>8.1%}  {caught_a:>8d}/50")

acc_b = accuracy_score(y_true, y_pred_model_b)
caught_b = (y_pred_model_b[y_true == 1] == 1).sum()
print(f"{'Actual model':25s}  {acc_b:>8.1%}  {caught_b:>8d}/50")

print()
print("Model A has HIGHER accuracy but catches ZERO incidents!")
print("Model B has LOWER accuracy but catches 40 out of 50 incidents!")
print()
print("For database monitoring, Model B is clearly better.")
print("Accuracy alone would tell you the opposite.")
PYEOF
```

Expected output (yours will differ):

```
Model                      Accuracy  Incidents Found
-------------------------------------------------------
Always predicts healthy       95.0%         0/50
Actual model                  96.0%        40/50

Model A has HIGHER accuracy but catches ZERO incidents!
```

---

## Step 2. Precision, Recall, and F1

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import precision_score, recall_score, f1_score, classification_report

np.random.seed(42)

print("""
Three metrics that tell the FULL story:

PRECISION: Of all predictions of "incident", how many were real incidents?
  Formula: True Positives / (True Positives + False Positives)
  High precision = few false alarms
  Use when: false alarms are costly (auto-restart servers, page the on-call)

RECALL: Of all actual incidents, how many did the model find?
  Formula: True Positives / (True Positives + False Negatives)
  High recall = few missed incidents
  Use when: missing events is costly (data loss, downtime)

F1 SCORE: The balance between precision and recall
  Formula: 2 * (precision * recall) / (precision + recall)
  Use when: you want a single number that considers both
""")

# Simulate predictions
n = 200
y_true = np.zeros(n, dtype=int)
y_true[:30] = 1  # 30 incidents out of 200 (15%)
np.random.shuffle(y_true)

# Three models with different trade-offs
# Model 1: Conservative (high precision, low recall)
y_pred_conservative = np.zeros(n, dtype=int)
incidents = np.where(y_true == 1)[0]
y_pred_conservative[incidents[:10]] = 1  # catches only 10/30 incidents, no false alarms

# Model 2: Aggressive (low precision, high recall)
y_pred_aggressive = np.zeros(n, dtype=int)
y_pred_aggressive[incidents] = 1         # catches all 30 incidents
false_alarm_idx = np.where(y_true == 0)[0][:40]
y_pred_aggressive[false_alarm_idx] = 1   # but 40 false alarms

# Model 3: Balanced
y_pred_balanced = np.zeros(n, dtype=int)
y_pred_balanced[incidents[:25]] = 1      # catches 25/30 incidents
y_pred_balanced[np.where(y_true == 0)[0][:8]] = 1  # 8 false alarms

print(f"{'Model':15s}  {'Precision':>10s}  {'Recall':>8s}  {'F1':>6s}  {'Accuracy':>9s}")
print("-" * 55)

for name, y_pred in [
    ("Conservative", y_pred_conservative),
    ("Aggressive", y_pred_aggressive),
    ("Balanced", y_pred_balanced),
]:
    prec = precision_score(y_true, y_pred)
    rec = recall_score(y_true, y_pred)
    f1 = f1_score(y_true, y_pred)
    acc = (y_true == y_pred).mean()
    print(f"{name:15s}  {prec:>9.1%}  {rec:>7.1%}  {f1:>5.1%}  {acc:>8.1%}")

print()
print("Conservative: rarely raises alerts, but when it does, it's almost always right")
print("Aggressive:   catches everything, but fires too many false alarms")
print("Balanced:     best F1 - good trade-off between precision and recall")
print()
print("For database alerts:")
print("  - If false alarms page the on-call at 3 AM -> prioritize PRECISION")
print("  - If missing a real incident causes data loss -> prioritize RECALL")
print("  - If both matter equally -> prioritize F1")
PYEOF
```

Expected output (yours will differ):

```
Model           Precision    Recall      F1  Accuracy
-------------------------------------------------------
Conservative      100.0%    33.3%   50.0%     90.0%
Aggressive         42.9%   100.0%   60.0%     80.0%
Balanced           75.8%    83.3%   79.4%     93.5%
```

---

## Step 3. The confusion matrix

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import confusion_matrix, classification_report

np.random.seed(42)

# Multi-class example: 4 alert categories
categories = ["performance", "storage", "replication", "security"]
n = 200

# Simulate true labels
y_true = np.random.choice([0, 1, 2, 3], size=n, p=[0.4, 0.25, 0.2, 0.15])
# p=[0.4, 0.25, 0.2, 0.15] sets the probability of each class
# Performance alerts are most common (40%)

# Simulate predictions (mostly correct, some confusion)
y_pred = y_true.copy()
# Add realistic confusion: storage and performance get confused
for i in range(n):
    if y_true[i] == 0 and np.random.random() < 0.15:
        y_pred[i] = 1  # performance confused with storage
    elif y_true[i] == 1 and np.random.random() < 0.20:
        y_pred[i] = 0  # storage confused with performance
    elif y_true[i] == 2 and np.random.random() < 0.10:
        y_pred[i] = 0  # replication confused with performance
    elif y_true[i] == 3 and np.random.random() < 0.05:
        y_pred[i] = 2  # security rarely confused

# Print confusion matrix
cm = confusion_matrix(y_true, y_pred)
# confusion_matrix returns a 2D array
# Rows = actual labels, Columns = predicted labels
# cm[i][j] = number of examples with true label i predicted as j

print("Confusion Matrix:")
print(f"{'':>15s}", end="")
for cat in categories:
    print(f"  {cat[:8]:>8s}", end="")
print("   <- predicted")
print("-" * 60)

for i, cat in enumerate(categories):
    print(f"{cat:>15s}", end="")
    for j in range(len(categories)):
        val = cm[i][j]
        marker = " " if i == j else "*" if val > 2 else " "
        print(f"  {val:>7d}{marker}", end="")
    print(f"   | total: {cm[i].sum()}")

print()
print("Read each ROW: where did 'performance' alerts actually go?")
print("Diagonal = correct predictions (should be large)")
print("Off-diagonal = errors (* marks significant confusion)")
print()

# Full classification report
print("Full Classification Report:")
print(classification_report(y_true, y_pred, target_names=categories))

print("Key insights:")
print("  - Storage and performance get confused (fix: better training data for the boundary)")
print("  - Security is rarely confused (it's very distinctive)")
print("  - Replication sometimes gets classified as performance (WAL/lag overlap)")
PYEOF
```

Expected output (yours will differ):

```
Confusion Matrix:
                 performa   storage   replica   securit   <- predicted
------------------------------------------------------------
    performance       68*       12        0        0    | total: 80
        storage       10        40        0        0    | total: 50
    replication        4         0       36        0    | total: 40
       security        0         0        2       28    | total: 30

Full Classification Report:
              precision    recall  f1-score   support
  performance       0.83      0.85      0.84        80
      storage       0.77      0.80      0.78        50
  replication       0.95      0.90      0.92        40
     security       1.00      0.93      0.97        30
```

---

## Step 4. Threshold tuning

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import precision_score, recall_score, f1_score

np.random.seed(42)

print("""
Threshold Tuning: Change the decision boundary to balance precision vs recall.

Default: predict "incident" if probability > 0.5
But you can change this:
  - threshold = 0.3 -> more incidents predicted (higher recall, lower precision)
  - threshold = 0.7 -> fewer incidents predicted (higher precision, lower recall)

DBA analogy: It's like setting the threshold for a monitoring alert.
  - CPU > 80% -> alert (catches more, more false alarms)
  - CPU > 95% -> alert (catches fewer, fewer false alarms)
""")

# Simulate: model outputs probabilities
n = 500
y_true = np.zeros(n, dtype=int)
y_true[:75] = 1  # 15% incident rate
np.random.shuffle(y_true)

# Simulated model probabilities (roughly correct)
# np.random.beta(2, 5, n) generates random numbers between 0 and 1
# with a specific shape (skewed toward lower values)
# Don't worry about the math - just know it makes realistic-looking probabilities
probs = np.random.beta(2, 5, n).astype(float)  # skewed toward low values
# For actual incidents, shift probabilities higher
probs[y_true == 1] += np.random.uniform(0.3, 0.6, y_true.sum())
probs = np.clip(probs, 0, 1)  # keep between 0 and 1
# np.clip(values, min, max) caps values at min and max

print(f"{'Threshold':>10s}  {'Precision':>10s}  {'Recall':>8s}  {'F1':>6s}  {'Predicted+':>11s}")
print("-" * 55)

best_f1 = 0
best_threshold = 0

for threshold in [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]:
    y_pred = (probs > threshold).astype(int)
    # Convert probabilities to binary predictions using threshold
    predicted_positive = y_pred.sum()

    if predicted_positive == 0:
        print(f"{threshold:>10.1f}  {'N/A':>10s}  {'N/A':>8s}  {'N/A':>6s}  {predicted_positive:>11d}")
        continue

    prec = precision_score(y_true, y_pred, zero_division=0)
    # zero_division=0 prevents errors when no positive predictions
    rec = recall_score(y_true, y_pred)
    f1 = f1_score(y_true, y_pred)

    marker = ""
    if f1 > best_f1:
        best_f1 = f1
        best_threshold = threshold
        marker = " <-- best F1"

    print(f"{threshold:>10.1f}  {prec:>9.1%}  {rec:>7.1%}  {f1:>5.1%}  {predicted_positive:>11d}{marker}")

print()
print(f"Best F1 threshold: {best_threshold}")
print()
print("For database monitoring:")
print("  - Use LOW threshold (0.3) if missing incidents is catastrophic")
print("  - Use HIGH threshold (0.7) if false alarms disrupt the team")
print("  - Use BEST F1 threshold if both matter equally")
PYEOF
```

Expected output (yours will differ):

```
 Threshold   Precision    Recall      F1  Predicted+
-------------------------------------------------------
       0.2       22.3%   100.0%   36.5%          337
       0.3       35.7%    97.3%   52.2%          204
       0.4       52.1%    90.7%   66.2%          130
       0.5       68.4%    82.7%   74.9%           91 <-- best F1
       0.6       81.0%    68.0%   73.9%           63
       0.7       90.2%    49.3%   63.8%           41
       0.8       95.2%    26.7%   41.7%           21
```

---

## Step 5. AUC-ROC - comparing models overall

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import roc_auc_score

np.random.seed(42)

print("""
AUC-ROC: Area Under the Receiver Operating Characteristic curve.

What it measures: How well does the model RANK positive examples
above negative examples, regardless of threshold?

AUC = 1.0: Perfect - all incidents ranked above all healthy servers
AUC = 0.5: Random - no better than a coin flip
AUC = 0.0: Perfectly wrong - all incidents ranked BELOW healthy servers

Why use it:
  - Doesn't depend on threshold choice
  - Good for comparing models against each other
  - Works well even with imbalanced data
""")

n = 1000
y_true = np.zeros(n, dtype=int)
y_true[:100] = 1
np.random.shuffle(y_true)

# Model A: Good model (incidents get high probabilities)
probs_a = np.random.beta(2, 5, n)
probs_a[y_true == 1] += np.random.uniform(0.3, 0.5, 100)
probs_a = np.clip(probs_a, 0, 1)

# Model B: Mediocre model (less separation)
probs_b = np.random.beta(2, 5, n)
probs_b[y_true == 1] += np.random.uniform(0.1, 0.3, 100)
probs_b = np.clip(probs_b, 0, 1)

# Model C: Random model
probs_c = np.random.uniform(0, 1, n)

auc_a = roc_auc_score(y_true, probs_a)
auc_b = roc_auc_score(y_true, probs_b)
auc_c = roc_auc_score(y_true, probs_c)

print(f"{'Model':15s}  {'AUC-ROC':>8s}  Interpretation")
print("-" * 55)
print(f"{'Good model':15s}  {auc_a:>7.3f}  Excellent ranking")
print(f"{'Mediocre model':15s}  {auc_b:>7.3f}  Acceptable but room for improvement")
print(f"{'Random model':15s}  {auc_c:>7.3f}  No better than chance")
print()
print("Use AUC-ROC to compare models before choosing a threshold")
print("Higher AUC = model is better at separating incidents from healthy")
PYEOF
```

---

## What You Learned

| Metric | What It Tells You | When to Use |
|--------|------------------|-------------|
| Accuracy | Overall correct % | Only for balanced datasets |
| Precision | False alarm rate | When false alarms are costly |
| Recall | Missed event rate | When missing events is costly |
| F1 | Balance of precision and recall | Most situations |
| Confusion matrix | Which classes get confused | Multi-class problems |
| Threshold tuning | Trade-off control | When you need to prioritize precision or recall |
| AUC-ROC | Overall model quality | Comparing models |
