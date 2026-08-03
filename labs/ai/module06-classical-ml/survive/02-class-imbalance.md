# SURVIVE 02: Class Imbalance - 99% Accuracy, Zero Incidents Caught

Your model reports 99% accuracy. Management is thrilled. But it has never correctly predicted a single incident. The "accuracy" is a lie.

---

## The Scenario

In production, server incidents are rare - only 1% of the time. A model that ALWAYS predicts "healthy" gets 99% accuracy. It catches zero incidents. Accuracy is the wrong metric.

---

## Step 1. See the useless model

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

np.random.seed(42)

# --- Realistic imbalanced data ---
# 1000 servers, only 1% have incidents
n = 1000
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)

# Only 10 out of 1000 servers have incidents
incident = np.zeros(n, dtype=int)
# Manually set 10 servers as incidents
incident_idx = np.random.choice(n, size=10, replace=False)
incident[incident_idx] = 1

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'memory_percent': memory, 'incident': incident,
})

print(f"Data: {n} servers")
print(f"Incidents: {incident.sum()} ({incident.mean()*100:.1f}%)")
print(f"Healthy:   {n - incident.sum()} ({(1-incident.mean())*100:.1f}%)")
print()

X = df.drop('incident', axis=1)
y = df['incident']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# --- Train a standard model ---
model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)
predictions = model.predict(X_test)

acc = accuracy_score(y_test, predictions)

print(f"Accuracy: {acc:.1%}  <- Looks great!")
print()

# But look at the confusion matrix
cm = confusion_matrix(y_test, predictions)
tn, fp, fn, tp = cm.ravel()
print("Confusion Matrix:")
print(f"  True Negatives:  {tn}")
print(f"  False Positives: {fp}")
print(f"  False Negatives: {fn}")
print(f"  True Positives:  {tp}")
print()

# The real story
print(f"Incidents in test set: {(y_test == 1).sum()}")
print(f"Incidents caught:      {tp}")
print(f"Incidents MISSED:      {fn}")
print()

if tp == 0:
    print("THE MODEL CAUGHT ZERO INCIDENTS!")
    print("It predicts 'healthy' for everything.")
    print("99% accuracy is meaningless when 99% of data is healthy.")
else:
    print(f"The model caught {tp}/{tp+fn} incidents")

print()
print("This is like a fire alarm that never goes off.")
print("'It never had a false alarm!' - because it never alarmed at all.")
PYEOF
```

Expected output (yours will differ):
```
Data: 1000 servers
Incidents: 10 (1.0%)
Healthy:   990 (99.0%)

Accuracy: 99.0%  <- Looks great!

Confusion Matrix:
  True Negatives:  198
  False Positives: 0
  False Negatives: 2
  True Positives:  0

Incidents in test set: 2
Incidents caught:      0
Incidents MISSED:      2

THE MODEL CAUGHT ZERO INCIDENTS!
It predicts 'healthy' for everything.
99% accuracy is meaningless when 99% of data is healthy.
```

---

## Step 2. Understand why accuracy fails

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
The accuracy paradox:

  1000 servers: 990 healthy, 10 incidents

  Model A (predicts ALL healthy):
    Correct: 990/1000 = 99.0% accuracy
    Incidents caught: 0/10 = 0% recall
    USELESS as a monitoring tool

  Model B (catches 8 out of 10 incidents, 20 false alarms):
    Correct: 968/1000 = 96.8% accuracy  <- LOWER accuracy
    Incidents caught: 8/10 = 80% recall
    MUCH more useful!

  Model A has higher accuracy but is completely useless.
  Model B has lower accuracy but actually catches incidents.

The fix: use metrics that account for class imbalance.

  ACCURACY:  "What % correct?"       -> misleading with imbalanced data
  PRECISION: "When it says incident,  -> important if false alarms are costly
              how often is it right?"
  RECALL:    "Of all incidents,       -> CRITICAL for monitoring (don't miss events)
              how many did it catch?"
  F1:        "Balance of precision    -> best single metric for imbalanced data
              and recall"

For DBA monitoring: RECALL is king. Missing an incident is worse than a false alarm.
""")
PYEOF
```

---

## Step 3. Fix with class weights and proper metrics

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score, recall_score, classification_report

np.random.seed(42)

# More data to make the problem clearer
n = 2000
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)

# 3% incident rate (realistic)
incident = np.zeros(n, dtype=int)
# Incidents happen when resources are high
high_resource = (cpu > 85) & (connections > 220)
incident[high_resource] = 1
# Add some random incidents
random_incidents = np.random.choice(n, size=20, replace=False)
incident[random_incidents] = 1

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'memory_percent': memory, 'incident': incident,
})

print(f"Data: {n} servers, {incident.sum()} incidents ({incident.mean()*100:.1f}%)")
print()

X = df.drop('incident', axis=1)
y = df['incident']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# --- Fix 1: class_weight='balanced' ---
# Tells the model to pay MORE attention to the rare class
# It increases the penalty for misclassifying incidents

models = {
    "Standard (broken)": LogisticRegression(random_state=42),
    "Balanced weights":  LogisticRegression(class_weight='balanced', random_state=42),
    "RF balanced":       RandomForestClassifier(n_estimators=100, class_weight='balanced', random_state=42),
}

print(f"{'Model':<22s} {'Accuracy':>9s} {'Recall':>8s} {'F1':>8s} {'Caught':>8s}")
print("-" * 58)

for name, model in models.items():
    model.fit(X_train, y_train)
    preds = model.predict(X_test)

    acc = accuracy_score(y_test, preds)
    rec = recall_score(y_test, preds, zero_division=0)
    f1 = f1_score(y_test, preds, zero_division=0)
    caught = ((preds == 1) & (y_test == 1)).sum()
    total_incidents = (y_test == 1).sum()

    print(f"{name:<22s} {acc:>8.1%} {rec:>8.1%} {f1:>7.3f} {caught:>3d}/{total_incidents}")

print()

# Show the best model's confusion matrix
best = RandomForestClassifier(n_estimators=100, class_weight='balanced', random_state=42)
best.fit(X_train, y_train)
print("Best model (RF balanced) classification report:")
print(classification_report(y_test, best.predict(X_test),
                           target_names=['Healthy', 'Incident']))

print("Key takeaways:")
print("  1. Standard model: high accuracy, low recall (misses incidents)")
print("  2. Balanced weights: lower accuracy, much higher recall (catches incidents)")
print("  3. For monitoring: always use class_weight='balanced'")
print("  4. Never report accuracy alone - always include recall and F1")
PYEOF
```

Expected output (yours will differ):
```
Data: 2000 servers, 60 incidents (3.0%)

Model                  Accuracy   Recall       F1   Caught
----------------------------------------------------------
Standard (broken)         97.5%    41.7%   0.556   5/12
Balanced weights          94.5%    83.3%   0.556  10/12
RF balanced               96.8%    75.0%   0.667   9/12

Best model (RF balanced) classification report:
              precision    recall  f1-score   support

     Healthy       1.00      0.97      0.98       388
    Incident       0.43      0.75      0.55        12

    accuracy                           0.97       400
   macro avg       0.71      0.86      0.77       400
weighted avg       0.98      0.97      0.97       400

Key takeaways:
  1. Standard model: high accuracy, low recall (misses incidents)
  2. Balanced weights: lower accuracy, much higher recall (catches incidents)
  3. For monitoring: always use class_weight='balanced'
  4. Never report accuracy alone - always include recall and F1
```

---

## Step 4. The complete checklist for imbalanced data

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Imbalanced Data Checklist:

1. CHECK the class distribution FIRST
   print(y.value_counts())
   If any class is < 10%, you have imbalance.

2. NEVER use accuracy as your only metric
   Use: F1, recall, precision, AUC-ROC
   For monitoring: prioritize recall

3. USE class_weight='balanced'
   LogisticRegression(class_weight='balanced')
   RandomForestClassifier(class_weight='balanced')
   This tells the model: "missing a rare event is MORE costly"

4. CONSIDER oversampling (SMOTE)
   from imblearn.over_sampling import SMOTE
   X_resampled, y_resampled = SMOTE().fit_resample(X_train, y_train)
   Creates synthetic examples of the rare class

5. LOWER the prediction threshold
   Instead of: predict "incident" if probability > 0.5
   Use:        predict "incident" if probability > 0.3
   Catches more incidents at the cost of more false alarms

6. ALWAYS look at the confusion matrix
   If False Negatives > 0 for a monitoring system, investigate.

DBA analogy:
  99% of the time, your database is fine.
  You don't need a monitoring system for the 99%.
  You need it for the 1%.
""")
PYEOF
```

---

## What You Learned

| Problem | Symptom | Fix |
|---------|---------|-----|
| Class imbalance | High accuracy, zero recall | Use class_weight='balanced' |
| Accuracy is misleading | 99% accuracy, catches nothing | Use F1 and recall instead |
| Model predicts majority class | All predictions are "healthy" | Lower threshold or use SMOTE |
| Missing incidents | False negatives > 0 | Prioritize recall for monitoring |
