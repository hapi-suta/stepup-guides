# SURVIVE: Concept drift

A model that scored 90% in training is now scoring 63% in production. Nobody
changed the code. What changed is the world. The data flowing in today does not
look like the data the model learned from. This is concept drift (also called
dataset shift), and every deployed model faces it eventually.

This runbook walks you through detecting the drift, diagnosing it, deciding
whether to retrain or retire, retraining, and setting up monitoring. Reference:
Concepts 4.6 (Concept drift and model monitoring).

Before you start, run the injector if you have not already:

```
bash inject.sh
```

That builds `~/survive-concept-drift`, generates two periods of data, trains the
deployed model on the old period, and runs the monitor against the new period.

---

## Layer 1: Detect

On your lab server, as ec2-user, move into the working directory. `cd` changes
your current directory so the commands find the files.

```
cd ~/survive-concept-drift
```

Activate the virtual environment. `source` loads the venv so `python` uses the
interpreter with scikit-learn installed.

```
source .venv/bin/activate
```

Run the monitor to see the live accuracy against production data. `monitor.py`
loads the deployed model_v1 and scores it on the new-period data.

```
python monitor.py
```

Expected output (yours will differ):

```
live_accuracy_period2: 0.6317

Feature-mean shift (period2 - period1):
  f1: +1.503  <-- SHIFTED
  f2: +1.498  <-- SHIFTED
  f3: +0.021
```

Two detection signals. First, live accuracy is 0.63, far below the 0.90 the
model reached in training - that gap is the alarm. Second, the feature means
have moved by about 1.5 on f1 and f2. The inputs the model sees today are not
the inputs it was trained on.

---

## Layer 2: Diagnose and decide

Confirm the training-time accuracy so you have the baseline to compare against.
`grep` in the injector output would work, but just retrain the baseline print by
re-running the original training script. `train_v1.py` prints the period-1
accuracy.

```
python train_v1.py
```

Expected output (yours will differ):

```
training_accuracy_period1: 0.8988
Saved model_v1.pkl
```

So the model went from 0.90 in training to 0.63 in production. That is a large,
sustained drop paired with a clear input-distribution shift. This is not a bad
day or a noisy sample - it is concept drift: the joint distribution of features
and label has changed, so the rule the model learned no longer holds.

Now the decision: retrain or retire?

- Retire makes sense when the use case is gone, the model is causing harm, or no
  fresh labeled data exists to learn a new rule.
- Retrain makes sense when the problem still matters and you have recent labeled
  data that reflects the new world.

Here the problem still matters and you have period-2 labeled data. So retrain on
recent data is the right call. Retiring would leave the business with no model
for a problem that is still live.

---

## Layer 3: Correct and validate

Write the retrain script. It trains a fresh model that includes the new-period
data (so it learns the current rule) and reports the recovered accuracy on
recent data. Open a new file with vi.

```
vi retrain.py
```

In vi, press `i` to enter insert mode, type the file below, then press `Esc` and
type `:wq` and press Enter to save and quit.

```python
"""Retrain a fresh model that includes recent (period-2) data.

The deployed model_v1 learned the period-1 rule, which no longer holds. We
retrain on data that includes the new period so the model learns the current
relationship, then evaluate on held-out recent data.
"""
import pandas as pd
import pickle
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

old = pd.read_csv("train_old.csv")
new = pd.read_csv("prod_new.csv")

# Combine both periods so the model sees the current world. On a real system
# you might weight recent data more heavily or use only recent data; here we
# include the new period so the current rule is learned.
data = pd.concat([old, new], ignore_index=True)
X = data[["f1", "f2", "f3"]]
y = data["label"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

model = RandomForestClassifier(n_estimators=200, random_state=42)
model.fit(X_train, y_train)

# Evaluate on held-out RECENT data - that is what production looks like now.
new_test = new.sample(frac=0.25, random_state=42)
X_new = new_test[["f1", "f2", "f3"]]
y_new = new_test["label"]
recovered = accuracy_score(y_new, model.predict(X_new))

print(f"retrained_accuracy_recent: {recovered:.4f}")

with open("model_v2.pkl", "wb") as fh:
    pickle.dump(model, fh)
print("Saved model_v2.pkl")
```

Run it. This trains model_v2 on both periods and prints the recovered accuracy
on recent data.

```
python retrain.py
```

Expected output (yours will differ):

```
retrained_accuracy_recent: 0.8842
Saved model_v2.pkl
```

Accuracy on recent data recovered from 0.63 back to about 0.88. The retrained
model learned the current rule, so it works on today's production data.

Now write up what you found. Open the findings file with vi.

```
vi drift_findings.md
```

Press `i`, write your findings, then `Esc` and `:wq`. Make sure you mention the
drift or shift, state your decision (retrain), and describe how you will monitor
going forward. Something like:

```markdown
# Concept drift findings

## Detection
model_v1 scored 0.90 in training (period 1) but only 0.63 on production
(period 2). The monitor also showed feature means for f1 and f2 shifted by
about +1.5 between periods. Large sustained accuracy drop plus an input
distribution shift.

## Diagnosis
Concept drift / dataset shift. The joint distribution of features and label
changed between period 1 and period 2, so the rule model_v1 learned no longer
matches production.

## Decision: retrain
The problem still matters and we have recent labeled data (period 2). Retiring
would leave the business with no model for a live problem, so retrain is the
right call. Retrained on data including the new period; accuracy on recent data
recovered from 0.63 to ~0.88 (model_v2).

## Monitoring going forward
- Track live accuracy on labeled production data and alert when it drops below a
  threshold vs the training baseline.
- Track feature-distribution shift (mean/PSI/KS) per feature and alert on
  significant moves.
- Schedule periodic retraining on recent data and keep a rollback to the prior
  model version.
```

Now validate your work. This runs the checker, which confirms your files exist,
retrain.py runs cleanly and recovers accuracy, and your findings cover the right
points.

```
bash validate.sh
```

Expected output (yours will differ):

```
=== Validating SURVIVE: concept-drift ===
OK:   drift_findings.md exists
OK:   findings mention drift or shift
OK:   findings state the retrain (or justified retire) decision
OK:   findings describe monitoring going forward
OK:   retrain.py exists
OK:   retrain.py runs clean
OK:   recovered accuracy 0.88 is materially above the drifted ~0.63
RESULT: PASS - drift detected, decision justified, and accuracy recovered
```

If you see RESULT: PASS you have survived the scenario.
