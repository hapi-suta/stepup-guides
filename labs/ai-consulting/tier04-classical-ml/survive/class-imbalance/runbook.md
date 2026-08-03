# SURVIVE: Class imbalance

An incident-detection model reports 97% accuracy and someone wants to ship it.
But real incidents are rare - about 3% of events. A model that always says "no
incident" would also score 97% and catch nothing. High accuracy on an
imbalanced problem tells you almost nothing.

This runbook walks you through exposing the useless model, diagnosing the
imbalance, fixing it, and re-evaluating on metrics that actually matter.
Reference: Concepts 4.5 (Evaluation metrics and class imbalance).

Before you start, run the injector if you have not already:

```
bash inject.sh
```

That builds `~/survive-class-imbalance`, generates the dataset, and runs the
naive training so you can see the misleading 97% result.

---

## Layer 1: Detect

On your lab server, as ec2-user, move into the working directory. `cd` changes
your current directory so the commands find the files.

```
cd ~/survive-class-imbalance
```

Activate the virtual environment. `source` loads the venv so `python` uses the
interpreter that already has scikit-learn installed.

```
source .venv/bin/activate
```

Check how rare the positive class is. `python -c` runs a one-line program; this
one prints the label counts so you can see the imbalance.

```
python -c "import pandas as pd; print(pd.read_csv('incidents.csv')['is_incident'].value_counts())"
```

Expected output (yours will differ):

```
is_incident
0    5817
1     183
Name: count, dtype: int64
```

Only about 3% of rows are incidents. That is the setup for a misleading
accuracy. Accuracy alone will not tell you if the model catches incidents. You
need the confusion matrix and per-class recall.

---

## Layer 2: Diagnose

Write a diagnosis script that prints the confusion matrix and a full
classification report, not just accuracy. Open a new file with vi.

```
vi diagnose.py
```

In vi, press `i` to enter insert mode, type the file below, then press `Esc` and
type `:wq` and press Enter to save and quit.

```python
"""Diagnose the naive model with metrics that expose the imbalance."""
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import confusion_matrix, classification_report

df = pd.read_csv("incidents.csv")
X = df.drop(columns=["is_incident"])
y = df["is_incident"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

model = LogisticRegression(max_iter=1000)
model.fit(X_train, y_train)
pred = model.predict(X_test)

print("Confusion matrix (rows = actual, cols = predicted):")
print(confusion_matrix(y_test, pred))
print("")
print(classification_report(y_test, pred, digits=3))
```

Run it. This retrains the same naive model and prints the confusion matrix and
per-class precision, recall, and f1.

```
python diagnose.py
```

Expected output (yours will differ):

```
Confusion matrix (rows = actual, cols = predicted):
[[1454    0]
 [  44    2]]

              precision    recall  f1-score   support

           0      0.971     1.000     0.985      1454
           1      1.000     0.043     0.083        46

    accuracy                          0.971      1500
   macro avg      0.985     0.522     0.534      1500
weighted avg      0.972     0.971     0.958      1500
```

Read the confusion matrix. Of 46 real incidents, the model caught 2 and missed
44. Recall on class 1 is 0.043 - about 5%. The model is essentially always
predicting "no incident." The 97% accuracy is entirely the majority class. This
is the classic class-imbalance failure: a high accuracy hiding a useless model.

---

## Layer 3: Correct and validate

The cheapest robust fix is to tell the classifier to weight the rare class more
heavily. `class_weight="balanced"` makes each class contribute equally to the
loss regardless of how many examples it has, so the model stops ignoring the
rare class. Write the corrected training. Open a new file with vi.

```
vi balanced_train.py
```

Press `i`, type the file below, then `Esc` and `:wq` to save.

```python
"""Corrected training that fixes the class imbalance.

Uses class_weight="balanced" so the rare positive class is not ignored.
Reports the confusion matrix and per-class recall, not just accuracy.
"""
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score,
    recall_score,
    confusion_matrix,
    classification_report,
)

df = pd.read_csv("incidents.csv")
X = df.drop(columns=["is_incident"])
y = df["is_incident"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

# The one-line fix: weight classes inversely to their frequency.
model = LogisticRegression(max_iter=1000, class_weight="balanced")
model.fit(X_train, y_train)
pred = model.predict(X_test)

acc = accuracy_score(y_test, pred)
pos_recall = recall_score(y_test, pred, pos_label=1)

print("Confusion matrix (rows = actual, cols = predicted):")
print(confusion_matrix(y_test, pred))
print("")
print(classification_report(y_test, pred, digits=3))
print(f"accuracy: {acc:.4f}")
print(f"positive_class_recall: {pos_recall:.4f}")
```

Run it. This retrains with balanced class weights and prints the new metrics.

```
python balanced_train.py
```

Expected output (yours will differ):

```
Confusion matrix (rows = actual, cols = predicted):
[[1301  153]
 [  13   33]]

              precision    recall  f1-score   support

           0      0.990     0.895     0.940      1454
           1      0.177     0.717     0.284        46

    accuracy                          0.889      1500
   macro avg      0.584     0.806     0.612      1500
weighted avg      0.965     0.889     0.920      1500

accuracy: 0.8893
positive_class_recall: 0.7174
```

Recall on the rare class jumped from about 0.05 to about 0.72. Overall accuracy
dipped from 0.97 to about 0.89, and that is the right trade. You now catch most
real incidents instead of almost none. On a rare-event problem, recall on the
positive class is the number that matters, not overall accuracy.

Note: balanced weights raise recall at the cost of some precision (more false
alarms). Whether that trade is acceptable is a business decision - for critical
incidents, missing a real one is usually far worse than a false alarm.

Now write up what you found. Open the findings file with vi.

```
vi imbalance_findings.md
```

Press `i`, write your findings, then `Esc` and `:wq`. Make sure you mention the
imbalance, recall, and the confusion matrix, and name your fix
(class_weight="balanced" or resampling/SMOTE). Something like:

```markdown
# Class imbalance findings

## Detection
The positive class (is_incident=1) is only ~3% of rows. The naive model
reported 0.97 accuracy but the confusion matrix showed it caught 2 of 46 real
incidents. Recall on the positive class was ~0.05. The high accuracy was just
the majority class.

## Diagnosis
Severe class imbalance. Accuracy is the wrong metric here because always
predicting the majority class scores ~0.97 while catching zero incidents.

## Fix
Retrained LogisticRegression with class_weight="balanced" so the rare class is
weighted inversely to its frequency. (Resampling/oversampling or SMOTE are
alternatives.) Positive-class recall rose from ~0.05 to ~0.72. Overall accuracy
dipped to ~0.89, which is an acceptable trade for catching real incidents.

## Going forward
Track per-class recall and the confusion matrix, not just accuracy. Pick the
operating threshold based on the cost of a missed incident vs a false alarm.
```

Now validate your work. This runs the checker, which confirms your files exist,
your balanced training runs cleanly, and your findings cover the right points.

```
bash validate.sh
```

Expected output (yours will differ):

```
=== Validating SURVIVE: class-imbalance ===
OK:   imbalance_findings.md exists
OK:   findings mention imbalance
OK:   findings mention recall
OK:   findings mention the confusion matrix
OK:   findings name a fix (class_weight/balanced/resample/SMOTE)
OK:   balanced_train.py exists
OK:   balanced_train.py runs clean
OK:   positive-class recall 0.72 is materially above the naive ~0.05
RESULT: PASS - imbalance detected, corrected, and rare-class recall recovered
```

If you see RESULT: PASS you have survived the scenario.
