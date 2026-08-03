# USE: Threshold Tuning

**Tier 4 - USE phase.** A classifier does not really output "yes" or "no". It outputs a probability, like 0.73. Something has to decide the cutoff: is 0.73 high enough to call "yes"? By default most tools use 0.5, but 0.5 is almost never the right business choice. In this exercise you train a small model, look at its probabilities, and move the threshold up and down to trade precision against recall on purpose - then you write down why, in business terms.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25.

**Prerequisite:** You have finished the Tier 4 BUILD phase and know what precision and recall mean. You are logged into your lab server and can edit files with vi.

**Goal:** See how moving the decision threshold changes precision and recall, pick a recall-favoring threshold and a precision-favoring threshold, and justify your choice to a stakeholder in plain language.

---

## Step 1: Go to your artifacts folder

On your **lab server**, as **ec2-user**:

```
cd ~/ml-artifacts
```

The `cd` command changes into the `ml-artifacts` folder you made earlier. If you do not have it yet, run `mkdir -p ~/ml-artifacts` first, then this command.

Expected output (yours will differ):

```
[ec2-user@lab-server ml-artifacts]$
```

The prompt ends in `ml-artifacts`, so you are in the right place.

---

## Step 2: Create a Python virtual environment

A virtual environment is a private, isolated box for this project's Python packages so they do not clash with the system. On your **lab server**, as **ec2-user**:

```
python3.12 -m venv .venv
```

`python3.12` is the Python interpreter. The `-m venv` part runs the built-in venv tool, and `.venv` is the folder name where the environment is created.

Expected output (yours will differ):

```
[ec2-user@lab-server ml-artifacts]$
```

No output means it worked. A new hidden `.venv` folder now exists.

---

## Step 3: Activate the environment

On your **lab server**, as **ec2-user**:

```
source .venv/bin/activate
```

The `source` command runs the activate script in your current shell so that `python` and `pip` now point inside the `.venv` box.

Expected output (yours will differ):

```
(.venv) [ec2-user@lab-server ml-artifacts]$
```

The `(.venv)` prefix on your prompt confirms the environment is active.

---

## Step 4: Install the libraries

On your **lab server**, as **ec2-user** (with `(.venv)` showing):

```
pip install scikit-learn pandas numpy
```

`pip` is Python's package installer. This downloads scikit-learn (the machine-learning toolkit), pandas (for tables), and numpy (for number arrays) into your virtual environment only.

Expected output (yours will differ):

```
Collecting scikit-learn
  Downloading scikit_learn-1.5.2-...whl (13.3 MB)
Collecting pandas
  Downloading pandas-2.2.3-...whl (12.6 MB)
...
Successfully installed joblib-1.4.2 numpy-2.1.3 pandas-2.2.3 ...
  scikit-learn-1.5.2 scipy-1.14.1 threadpoolctl-3.5.0
```

The final `Successfully installed` line means all packages are ready.

---

## Step 5: Write the threshold-tuning script with vi

On your **lab server**, as **ec2-user**:

```
vi threshold_tuning.py
```

The `vi` command opens the editor with a new empty file named `threshold_tuning.py`.

Press `i` and enter:

```
# threshold_tuning.py
# Train a small classifier, then sweep the decision threshold
# to trade precision against recall on purpose.

import numpy as np
from sklearn.datasets import make_classification
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import precision_score, recall_score

# random_state=42 makes this reproducible: you get the same
# numbers every run, and the same numbers we show below.
RANDOM_STATE = 42

# Build a small, class-imbalanced dataset: only about 10 percent
# of rows are the positive class (weights=[0.9, 0.1]). This mimics
# real problems like fraud or churn where "yes" is rare.
X, y = make_classification(
    n_samples=2000,
    n_features=10,
    n_informative=5,
    weights=[0.9, 0.1],
    random_state=RANDOM_STATE,
)

# Split into training data (to learn from) and test data (to judge).
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.30, random_state=RANDOM_STATE
)

# Train a logistic regression classifier.
model = LogisticRegression(max_iter=1000, random_state=RANDOM_STATE)
model.fit(X_train, y_train)

# predict_proba gives the probability of the positive class (column 1)
# for every test row. These are the raw scores we will threshold.
probs = model.predict_proba(X_test)[:, 1]

# Sweep thresholds from 0.1 to 0.9 and measure precision and recall
# at each. A prediction is "yes" when its probability >= threshold.
print(f"{'threshold':>9} {'precision':>9} {'recall':>7} {'flagged':>7}")
print("-" * 36)
for t in np.arange(0.1, 0.91, 0.1):
    preds = (probs >= t).astype(int)
    p = precision_score(y_test, preds, zero_division=0)
    r = recall_score(y_test, preds, zero_division=0)
    flagged = int(preds.sum())
    print(f"{t:>9.1f} {p:>9.2f} {r:>7.2f} {flagged:>7}")

# Show the default 0.5 result explicitly for comparison.
default_preds = (probs >= 0.5).astype(int)
print()
print("Default threshold 0.5:")
print(f"  precision = {precision_score(y_test, default_preds):.2f}")
print(f"  recall    = {recall_score(y_test, default_preds):.2f}")
```

Press `Esc`, type `:wq`, press Enter.

`Esc` leaves insert mode, and `:wq` writes the file and quits vi.

---

## Step 6: Run the script

On your **lab server**, as **ec2-user** (with `(.venv)` showing):

```
python threshold_tuning.py
```

`python` runs your script. It trains the model, gets probabilities, and prints one row per threshold showing precision, recall, and how many rows were flagged "yes".

Expected output (yours will differ):

```
threshold precision  recall flagged
------------------------------------
      0.1      0.36    0.93      153
      0.2      0.48    0.85      105
      0.3      0.58    0.78       80
      0.4      0.68    0.68       59
      0.5      0.76    0.58       45
      0.6      0.83    0.47       34
      0.7      0.88    0.37       25
      0.8      0.93    0.25       16
      0.9      1.00    0.12        7

Default threshold 0.5:
  precision = 0.76
  recall    = 0.58
```

Read the pattern: as the threshold goes UP, precision goes up (the "yes" calls we make are more often right) but recall goes down (we catch fewer of the real positives). As the threshold goes DOWN, we catch more real positives but with more false alarms. There is no free lunch - you choose which mistake you can better afford.

---

## Step 7: Pick two thresholds on purpose

Look at your table and choose two working points.

- A recall-favoring threshold. From the table above, `0.2` catches 85 percent of the positives (recall 0.85). Use this when missing a positive is expensive.
- A precision-favoring threshold. `0.7` is right 88 percent of the time it says "yes" (precision 0.88). Use this when a false alarm is expensive or annoying.

The default `0.5` sits in the middle (precision 0.76, recall 0.58). Notice it catches barely over half the positives - fine for some problems, bad for fraud or churn where misses hurt.

There is no code for this step. The point is that YOU choose the threshold from the business cost of mistakes, not the tool's default.

---

## Step 8: Write the stakeholder justification with vi

A number in a table means nothing to an executive. You have to explain the tradeoff in their language. On your **lab server**, as **ec2-user**:

```
vi threshold-justification.md
```

vi opens a new empty file named `threshold-justification.md`.

Press `i` and enter (this example frames it as a fraud-detection decision):

```
# Threshold Recommendation: Fraud Screening

## The choice
Our model scores each transaction from 0 to 1 for how likely it is to
be fraud. We must pick the cutoff above which we flag a transaction for
review. The tool's default is 0.5. We recommend lowering it to 0.2.

## Why lower, not default
At the default 0.5 the model catches only about 58 percent of fraud.
Roughly 4 in every 10 fraudulent transactions slip through. Each missed
fraud is a direct financial loss plus a chargeback fee.

At a 0.2 threshold the model catches about 85 percent of fraud. We miss
far fewer bad transactions. The cost is more false alarms: some honest
transactions get flagged for a quick review.

## Why that is the right call for this business
For us, a missed fraud costs real money and customer trust. A false
alarm costs a few minutes of a reviewer's time, and the customer is
rarely even aware. The two mistakes are not equal, so a 50/50 cutoff is
wrong. We deliberately accept more false alarms to stop more fraud.

## Guardrail
Lowering the threshold flags more transactions (about 105 of 600 in
testing versus 45 at default). Before rollout we confirm the review
team can handle that volume. If the queue is too big, we settle at 0.3
(catches 78 percent, flags fewer), and revisit as staffing grows.

## Bottom line
Recommend threshold 0.2 for launch, with 0.3 as a fallback if review
capacity is tight. Revisit monthly as fraud patterns and staffing
change.
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 9: Read your justification back

On your **lab server**, as **ec2-user**:

```
cat threshold-justification.md
```

The `cat` command prints the file so you can re-read your argument end to end and check it would make sense to a non-technical manager.

Expected output (yours will differ):

```
# Threshold Recommendation: Fraud Screening

## The choice
Our model scores each transaction from 0 to 1 ...
...
## Bottom line
Recommend threshold 0.2 for launch, with 0.3 as a fallback ...
```

---

## Step 10: Deactivate the environment

When you are done, leave the virtual environment. On your **lab server**, as **ec2-user**:

```
deactivate
```

The `deactivate` command exits the virtual environment and returns `python` and `pip` to the system defaults.

Expected output (yours will differ):

```
[ec2-user@lab-server ml-artifacts]$
```

The `(.venv)` prefix is gone, confirming you are back to the normal shell.

---

## What you learned

- A classifier outputs probabilities, and the threshold turns those into decisions. The default 0.5 is a starting point, not an answer.
- Raising the threshold buys precision at the cost of recall; lowering it does the reverse.
- The right threshold comes from the business cost of each mistake, and you must be able to explain that tradeoff in plain language to the people who own the risk.
