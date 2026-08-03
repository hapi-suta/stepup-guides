# Build 03: Random Forest + Proper Evaluation

A random forest builds many decision trees and takes a vote. It's more accurate than a single tree and harder to overfit. This is the model most data scientists reach for first.

---

## Step 1. Random forest - many trees voting together

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report

# --- Create data ---
np.random.seed(42)
n = 300  # more data for a more complex model

cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)
disk = np.random.uniform(10, 95, n)
wal_growth = np.random.uniform(0, 50, n)

# More complex rule with multiple conditions
incident = (
    ((cpu > 70) & (connections > 180)) |
    ((cpu > 85) & (memory > 80)) |
    ((disk > 85) & (wal_growth > 30)) |
    ((connections > 250) & (memory > 70))
).astype(int)

noise_mask = np.random.random(n) < 0.05
incident[noise_mask] = 1 - incident[noise_mask]

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'memory_percent': memory, 'disk_percent': disk,
    'wal_growth_mb': wal_growth, 'incident': incident,
})

X = df.drop('incident', axis=1)
y = df['incident']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

print(f"Data: {n} servers, {X.shape[1]} features")
print(f"Incidents: {y.sum()} ({y.mean()*100:.1f}%)")
print()

# --- Train random forest ---
# n_estimators = how many trees to build (100 is a good default)
# Each tree sees a random sample of the data and random features
# The final prediction is a majority vote across all trees
rf = RandomForestClassifier(
    n_estimators=100,    # build 100 trees
    max_depth=5,         # each tree can be 5 levels deep
    random_state=42,
)
rf.fit(X_train, y_train)

predictions = rf.predict(X_test)
accuracy = accuracy_score(y_test, predictions)

print(f"Random Forest Accuracy: {accuracy*100:.1f}%")
print()
print("Classification Report:")
print(classification_report(y_test, predictions,
                           target_names=['Healthy', 'Incident']))

# --- Feature importance ---
print("Feature importance (what drives incidents):")
for feature, importance in sorted(
    zip(X.columns, rf.feature_importances_),
    key=lambda x: x[1], reverse=True
):
    bar = "#" * int(importance * 50)
    print(f"  {feature:17s}: {importance:.3f} {bar}")

print()
print("How random forest works:")
print("  1. Build 100 decision trees, each trained on a random subset of data")
print("  2. Each tree also only sees a random subset of features")
print("  3. To predict: every tree votes, majority wins")
print("  4. Like asking 100 DBAs - the group is smarter than any individual")
PYEOF
```

Expected output (yours will differ):
```
Data: 300 servers, 5 features
Incidents: 81 (27.0%)

Random Forest Accuracy: 93.3%

Classification Report:
              precision    recall  f1-score   support

     Healthy       0.95      0.96      0.95        45
    Incident       0.88      0.87      0.87        15

    accuracy                           0.93        60
   macro avg       0.91      0.91      0.91        60
weighted avg       0.93      0.93      0.93        60

Feature importance (what drives incidents):
  cpu_percent      : 0.285 ##############
  connections      : 0.262 #############
  memory_percent   : 0.195 #########
  disk_percent     : 0.141 #######
  wal_growth_mb    : 0.117 #####
```

---

## Step 2. Cross-validation - more reliable evaluation

A single train/test split can be lucky or unlucky. Cross-validation tests the model multiple times with different splits and averages the results.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import cross_val_score
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.tree import DecisionTreeClassifier

# --- Same data ---
np.random.seed(42)
n = 300
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)
disk = np.random.uniform(10, 95, n)
wal_growth = np.random.uniform(0, 50, n)
incident = (
    ((cpu > 70) & (connections > 180)) |
    ((cpu > 85) & (memory > 80)) |
    ((disk > 85) & (wal_growth > 30)) |
    ((connections > 250) & (memory > 70))
).astype(int)
noise_mask = np.random.random(n) < 0.05
incident[noise_mask] = 1 - incident[noise_mask]

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'memory_percent': memory, 'disk_percent': disk,
    'wal_growth_mb': wal_growth, 'incident': incident,
})

X = df.drop('incident', axis=1)
y = df['incident']

# --- Cross-validation ---
# Instead of one 80/20 split, do 5 different splits:
#   Fold 1: Train on folds 2-5, test on fold 1
#   Fold 2: Train on folds 1,3-5, test on fold 2
#   ... and so on
# Average the 5 test scores for a more reliable estimate

# cross_val_score() does this automatically
# cv=5 means "5 folds" (5 different train/test splits)
# scoring='f1' uses F1 score instead of accuracy

models = {
    "Logistic Regression": LogisticRegression(random_state=42, max_iter=1000),
    "Decision Tree (d=4)": DecisionTreeClassifier(max_depth=4, random_state=42),
    "Random Forest (100)": RandomForestClassifier(n_estimators=100, max_depth=5, random_state=42),
}

print("5-Fold Cross-Validation Results")
print("=" * 65)
print(f"{'Model':<25s} {'Mean F1':>8s} {'Std':>7s}  {'Fold scores'}")
print("-" * 65)

for name, model in models.items():
    # cross_val_score returns a score for each fold
    scores = cross_val_score(model, X, y, cv=5, scoring='f1')

    # .mean() = average across folds
    # .std() = how much the score varies between folds
    fold_str = ", ".join(f"{s:.3f}" for s in scores)
    print(f"{name:<25s} {scores.mean():>7.3f} {scores.std():>7.3f}  [{fold_str}]")

print()
print("Reading the results:")
print("  Mean F1: average performance across 5 different test sets")
print("  Std:     how consistent the model is (lower = more stable)")
print("  If std is high, the model's performance depends on which data it sees")
print()
print("Cross-validation is like testing a query plan on 5 different databases,")
print("not just one. More trustworthy than a single test.")
PYEOF
```

Expected output (yours will differ):
```
5-Fold Cross-Validation Results
=================================================================
Model                     Mean F1     Std  Fold scores
-----------------------------------------------------------------
Logistic Regression         0.752   0.054  [0.750, 0.800, 0.667, 0.762, 0.783]
Decision Tree (d=4)         0.823   0.071  [0.889, 0.857, 0.706, 0.826, 0.838]
Random Forest (100)         0.856   0.048  [0.889, 0.875, 0.778, 0.870, 0.868]

Reading the results:
  Mean F1: average performance across 5 different test sets
  Std:     how consistent the model is (lower = more stable)
  If std is high, the model's performance depends on which data it sees

Cross-validation is like testing a query plan on 5 different databases,
not just one. More trustworthy than a single test.
```

Random forest wins: highest F1 AND lowest std (most consistent).

---

## Step 3. Confusion matrix - see exactly where the model fails

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import confusion_matrix

# --- Same data, quick setup ---
np.random.seed(42)
n = 300
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)
disk = np.random.uniform(10, 95, n)
wal_growth = np.random.uniform(0, 50, n)
incident = (
    ((cpu > 70) & (connections > 180)) | ((cpu > 85) & (memory > 80)) |
    ((disk > 85) & (wal_growth > 30)) | ((connections > 250) & (memory > 70))
).astype(int)
noise_mask = np.random.random(n) < 0.05
incident[noise_mask] = 1 - incident[noise_mask]

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections, 'memory_percent': memory,
    'disk_percent': disk, 'wal_growth_mb': wal_growth, 'incident': incident,
})

X = df.drop('incident', axis=1)
y = df['incident']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

rf = RandomForestClassifier(n_estimators=100, max_depth=5, random_state=42)
rf.fit(X_train, y_train)
predictions = rf.predict(X_test)

# --- Confusion matrix ---
# Shows exactly how many predictions were right/wrong and HOW they were wrong
cm = confusion_matrix(y_test, predictions)

# cm is a 2x2 matrix:
#                    Predicted
#                  Healthy  Incident
#   Actual Healthy   TN       FP
#   Actual Incident  FN       TP
#
# TN = True Negative:  model said healthy, actually healthy (correct)
# FP = False Positive: model said incident, actually healthy (false alarm)
# FN = False Negative: model said healthy, actually incident (MISSED!)
# TP = True Positive:  model said incident, actually incident (correct)

tn, fp, fn, tp = cm.ravel()  # .ravel() flattens to a 1D array

print("Confusion Matrix")
print("=" * 45)
print(f"                 Predicted Healthy  Predicted Incident")
print(f"  Actual Healthy:       {tn:>3d} (TN)           {fp:>3d} (FP)")
print(f"  Actual Incident:      {fn:>3d} (FN)           {tp:>3d} (TP)")
print()
print(f"  True Negatives (TN):  {tn:>3d} - correctly identified as healthy")
print(f"  False Positives (FP): {fp:>3d} - false alarms (said incident, was healthy)")
print(f"  False Negatives (FN): {fn:>3d} - MISSED incidents (said healthy, was incident)")
print(f"  True Positives (TP):  {tp:>3d} - correctly caught incidents")
print()

# Calculate metrics from the confusion matrix
precision = tp / (tp + fp) if (tp + fp) > 0 else 0
recall = tp / (tp + fn) if (tp + fn) > 0 else 0
accuracy = (tp + tn) / (tp + tn + fp + fn)

print(f"Precision: {precision:.3f} - {precision*100:.0f}% of predicted incidents were real")
print(f"Recall:    {recall:.3f} - {recall*100:.0f}% of real incidents were caught")
print(f"Accuracy:  {accuracy:.3f} - {accuracy*100:.0f}% overall correct")
print()

print("For a DBA monitoring system:")
print(f"  False Positives ({fp}): annoying but not dangerous (false alarms)")
print(f"  False Negatives ({fn}): DANGEROUS - real incidents the model missed!")
print(f"  In production, you want recall close to 1.0 (catch every incident)")
print(f"  A few false alarms are OK. Missing a real incident is not.")
PYEOF
```

Expected output (yours will differ):
```
Confusion Matrix
=============================================
                 Predicted Healthy  Predicted Incident
  Actual Healthy:        43 (TN)             2 (FP)
  Actual Incident:        2 (FN)            13 (TP)

  True Negatives (TN):   43 - correctly identified as healthy
  False Positives (FP):    2 - false alarms (said incident, was healthy)
  False Negatives (FN):    2 - MISSED incidents (said healthy, was incident)
  True Positives (TP):   13 - correctly caught incidents

Precision: 0.867 - 87% of predicted incidents were real
Recall:    0.867 - 87% of real incidents were caught
Accuracy:  0.933 - 93% overall correct

For a DBA monitoring system:
  False Positives (2): annoying but not dangerous (false alarms)
  False Negatives (2): DANGEROUS - real incidents the model missed!
  In production, you want recall close to 1.0 (catch every incident)
  A few false alarms are OK. Missing a real incident is not.
```

---

## Step 4. Threshold tuning - catch more incidents

By default, the model predicts "incident" when probability > 0.5. Lowering the threshold catches more incidents (higher recall) at the cost of more false alarms.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import precision_score, recall_score, f1_score

# --- Quick setup ---
np.random.seed(42)
n = 300
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)
disk = np.random.uniform(10, 95, n)
wal_growth = np.random.uniform(0, 50, n)
incident = (
    ((cpu > 70) & (connections > 180)) | ((cpu > 85) & (memory > 80)) |
    ((disk > 85) & (wal_growth > 30)) | ((connections > 250) & (memory > 70))
).astype(int)
noise_mask = np.random.random(n) < 0.05
incident[noise_mask] = 1 - incident[noise_mask]

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections, 'memory_percent': memory,
    'disk_percent': disk, 'wal_growth_mb': wal_growth, 'incident': incident,
})

X = df.drop('incident', axis=1)
y = df['incident']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

rf = RandomForestClassifier(n_estimators=100, max_depth=5, random_state=42)
rf.fit(X_train, y_train)

# Get probabilities (not just yes/no)
probabilities = rf.predict_proba(X_test)[:, 1]  # probability of incident

# --- Try different thresholds ---
print("Threshold tuning: trade false alarms for catching more incidents")
print("=" * 70)
print(f"{'Threshold':>10s}  {'Precision':>10s}  {'Recall':>10s}  {'F1':>10s}  Note")
print("-" * 70)

for threshold in [0.7, 0.5, 0.4, 0.3, 0.2, 0.1]:
    # predictions based on custom threshold instead of default 0.5
    preds = (probabilities >= threshold).astype(int)

    if preds.sum() == 0:  # no positive predictions
        print(f"{threshold:>10.1f}  {'N/A':>10s}  {'0.000':>10s}  {'N/A':>10s}  No incidents predicted")
        continue

    prec = precision_score(y_test, preds, zero_division=0)
    rec = recall_score(y_test, preds, zero_division=0)
    f1 = f1_score(y_test, preds, zero_division=0)

    note = ""
    if rec >= 0.95:
        note = "<- catches nearly all incidents"
    elif threshold == 0.5:
        note = "<- default"

    print(f"{threshold:>10.1f}  {prec:>10.3f}  {rec:>10.3f}  {f1:>10.3f}  {note}")

print()
print("Lower threshold = more incidents caught (higher recall)")
print("                 = more false alarms (lower precision)")
print()
print("Choose based on your use case:")
print("  - DBA alert system: low threshold (0.2-0.3). Don't miss incidents.")
print("  - Capacity planning: default (0.5). Balance is fine.")
print("  - Auto-remediation: high threshold (0.7+). Only act when very sure.")
PYEOF
```

Expected output (yours will differ):
```
Threshold tuning: trade false alarms for catching more incidents
======================================================================
 Threshold   Precision      Recall          F1  Note
----------------------------------------------------------------------
       0.7       1.000       0.733       0.846
       0.5       0.867       0.867       0.867  <- default
       0.4       0.813       0.867       0.839
       0.3       0.722       0.867       0.788
       0.2       0.619       0.867       0.722
       0.1       0.500       1.000       0.667  <- catches nearly all incidents

Lower threshold = more incidents caught (higher recall)
                 = more false alarms (lower precision)

Choose based on your use case:
  - DBA alert system: low threshold (0.2-0.3). Don't miss incidents.
  - Capacity planning: default (0.5). Balance is fine.
  - Auto-remediation: high threshold (0.7+). Only act when very sure.
```

---

## What You Learned

| Concept | What It Is | Why It Matters |
|---------|-----------|----------------|
| Random Forest | 100 trees voting together | Best out-of-the-box algorithm for tabular data |
| n_estimators | Number of trees | More trees = more accurate (but slower) |
| Cross-validation | Test on 5 different splits | More reliable than one train/test split |
| Confusion matrix | TN/FP/FN/TP breakdown | See exactly WHERE the model fails |
| False negative | Model missed a real incident | Most dangerous error for monitoring |
| Threshold tuning | Adjust the yes/no cutoff | Trade precision for recall based on use case |
| Feature importance | Which features drive predictions | Helps explain the model and find key metrics |
