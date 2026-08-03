# SURVIVE: Data leakage

A fraud model just reported 99% accuracy. Your manager is thrilled. You should
be worried. On a real fraud problem, near-perfect accuracy almost always means
a feature is leaking the answer into training - a column that will not exist
when you actually make predictions.

This runbook walks you through detecting the leak, fixing it, and re-evaluating
honestly. Reference: Concepts 4.4 (Data leakage in supervised learning).

Before you start, run the injector if you have not already:

```
bash inject.sh
```

That builds `~/survive-data-leakage`, generates the dataset, and runs the naive
training so you can see the misleading 99% result.

---

## Layer 1: Detect

On your lab server, as ec2-user, move into the working directory. `cd` changes
your current directory so the rest of the commands find the files.

```
cd ~/survive-data-leakage
```

Activate the virtual environment. `source` loads the venv so `python` points at
the interpreter that already has scikit-learn installed.

```
source .venv/bin/activate
```

Re-run the naive training so the result is fresh in front of you. This runs the
leaky `train.py` and prints its accuracy and feature importances.

```
python train.py
```

Expected output (yours will differ):

```
Features used: ['amount', 'num_prior_claims', 'account_age_days', 'hour_of_day', 'refund_issued']
accuracy: 0.9910

Feature importances:
  refund_issued: 0.9421
  amount: 0.0284
  num_prior_claims: 0.0161
  account_age_days: 0.0092
  hour_of_day: 0.0042
```

Two red flags. First, 0.99 accuracy on fraud is too good to be true. Second,
one feature (`refund_issued`) accounts for about 94% of the importance while
every real signal is near zero. When a single feature dominates that hard, ask
whether it is secretly a copy of the label.

---

## Layer 2: Diagnose and fix

Look at the raw data to understand each column. `head` prints the first lines of
the file so you can see the columns and some values.

```
head fraud.csv
```

Expected output (yours will differ):

```
amount,num_prior_claims,account_age_days,hour_of_day,refund_issued,is_fraud
605.14,1,712,3,0,0
978.44,4,88,17,1,1
441.02,0,540,9,0,0
812.77,3,151,22,1,1
...
```

Notice `refund_issued` matches `is_fraud` on almost every row. Now reason about
timing, which is the real test for leakage. Ask of each feature: "Would I know
this value at the moment I need to predict?"

- `amount`, `num_prior_claims`, `account_age_days`, `hour_of_day`: known when
  the claim arrives. Fine.
- `refund_issued`: a refund is only issued AFTER a case is investigated and
  confirmed as fraud. At prediction time the case is not yet resolved, so this
  value does not exist. It leaked the answer backwards into training.

That is the leak. `refund_issued` is a proxy for the label, not available at
prediction time.

Now write the honest training that drops the leak. Open a new file with vi. `vi`
opens the editor; the argument is the file name to create.

```
vi honest_train.py
```

In vi, press `i` to enter insert mode, then type the file below. When done,
press `Esc`, then type `:wq` and press Enter to save and quit.

```python
"""Honest training: drop the leaked feature, then evaluate.

refund_issued is set from the outcome and is not known at prediction time,
so it must not be a feature.
"""
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

df = pd.read_csv("fraud.csv")

# Drop the label AND the leaked column.
LEAKED = "refund_issued"
X = df.drop(columns=["is_fraud", LEAKED])
y = df["is_fraud"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

model = RandomForestClassifier(n_estimators=200, random_state=42)
model.fit(X_train, y_train)

pred = model.predict(X_test)
acc = accuracy_score(y_test, pred)

print("Dropped leaked feature:", LEAKED)
print("Features used:", list(X.columns))
print(f"accuracy: {acc:.4f}")
```

Run it. This retrains without the leak and prints the honest accuracy.

```
python honest_train.py
```

Expected output (yours will differ):

```
Dropped leaked feature: refund_issued
Features used: ['amount', 'num_prior_claims', 'account_age_days', 'hour_of_day']
accuracy: 0.8210
```

The accuracy fell from 0.99 to about 0.82. That is not a regression - it is the
truth. The 0.99 was the leak talking. 0.82 is what the model can actually do on
data it will see in production.

---

## Layer 3: Document and validate

Write up what you found. Open the findings file with vi.

```
vi leakage_findings.md
```

Press `i`, write your findings, then `Esc` and `:wq` to save. Make sure you
name the leaked feature, say the words "leak" or "leakage", and explain that the
feature is not available at prediction time. Something like:

```markdown
# Data leakage findings

## The leaked feature
The leaked feature was `refund_issued`.

## Why it leaked
`refund_issued` is set only after a case is investigated and confirmed as fraud.
It is a proxy for the label. At prediction time the case is not yet resolved, so
this value is not available. Including it let the model read the answer during
training, which is data leakage.

## Impact
Naive accuracy: 0.99 (misleading, driven ~94% by the leaked feature).
Honest accuracy after dropping the leak: 0.82.

## Fix
Dropped `refund_issued` and retrained. The remaining features (amount,
num_prior_claims, account_age_days, hour_of_day) are all knowable at prediction
time.

## Going forward
Audit every feature by asking "is this known at prediction time?" Be suspicious
of any single feature that dominates importance or any accuracy that looks too
good to be true.
```

Now validate your work. This runs the checker, which confirms your files exist,
your honest training runs cleanly, and your findings name the leak.

```
bash validate.sh
```

Expected output (yours will differ):

```
=== Validating SURVIVE: data-leakage ===
OK:   leakage_findings.md exists
OK:   findings name the leaked feature (refund_issued)
OK:   findings mention leakage
OK:   findings mention prediction-time availability
OK:   honest_train.py exists
OK:   honest_train.py runs clean
OK:   honest accuracy 0.82 is materially below the naive 0.99
RESULT: PASS - leak identified, dropped, and honest metrics reported
```

If you see RESULT: PASS you have survived the scenario.
