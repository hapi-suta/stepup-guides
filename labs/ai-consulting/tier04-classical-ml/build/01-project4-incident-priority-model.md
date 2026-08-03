# BUILD: Project 4 - Cybersecurity Incident-Priority Model

**Tier 4 - the "make ML earn its keep" build.** You will build a real machine-learning system end to end: a classifier that reads security incidents and predicts how severe each one is, so an overloaded security team knows what to work on first. You will train several models, compare them honestly, explain which features drive the predictions, write down where the model can hurt someone (false positives and false negatives), produce a model card, and finally serve live predictions from a FastAPI endpoint.

No black boxes. Every step is small, every command is explained, and every number is reproducible because we fix the random seed.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25. Output shown is real in shape (exact digits depend on library versions and will differ slightly).

**Prerequisite:** you read Concepts 4.1 (ML lifecycle), 4.2 (supervised learning), 4.4 (feature engineering), and 4.5 (model evaluation).

**What you build:** a folder `build-incident-priority/` containing:

- `generate_data.py` - makes a small, reproducible synthetic incident dataset
- `explore.py` - looks at the data before modelling
- `train_compare.py` - trains and compares logistic regression, random forest, and gradient boosting
- `importance.py` - explains which features matter most
- `error_analysis.py` - measures false-positive and false-negative risk
- `model_card.md` - the one-page honesty document you ship with the model
- `save_model.py` - trains the winner and saves it to disk
- `serve.py` - a FastAPI endpoint that returns a priority for a new incident

Everything runs on a CPU. The dataset is tiny on purpose so each script finishes in a second or two.

---

## Step 1: Create the project folder

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/build-incident-priority
```

The `mkdir` command makes a directory. The `-p` flag means "create parents if needed and do not error if it already exists".

Move into it:

```bash
cd ~/build-incident-priority
```

`cd` changes your current directory so the rest of the commands run inside the project folder.

---

## Step 2: Create and activate a virtual environment

A virtual environment (venv) is an isolated Python setup. Packages you install here do not touch the rest of the system, so you can never break the server's Python.

Still on your **lab server**, as **ec2-user**, in `~/build-incident-priority`:

```bash
python3.12 -m venv .venv
```

`python3.12 -m venv` runs the built-in venv tool. `.venv` is the folder name it creates for the isolated environment.

Activate it:

```bash
source .venv/bin/activate
```

`source` runs the activate script in your current shell so `python` and `pip` now point at the isolated environment. Your prompt now shows `(.venv)`.

---

## Step 3: Install the libraries

Still in the activated environment:

```bash
pip install scikit-learn pandas numpy joblib "fastapi" "uvicorn[standard]"
```

What each does:

- `scikit-learn` - the machine-learning toolkit (models, metrics, splitting).
- `pandas` - tables (DataFrames) for handling the dataset.
- `numpy` - fast numeric arrays underneath everything.
- `joblib` - saves a trained model to a file so we can load it later.
- `fastapi` - the web framework for the prediction endpoint.
- `uvicorn[standard]` - the server that runs the FastAPI app.

Confirm the core libraries installed:

```bash
pip list | grep -Ei "scikit-learn|pandas|numpy|fastapi"
```

`pip list` prints installed packages. `grep -Ei` filters to lines matching any of these names, case-insensitively (`-i`) using extended regex (`-E`).

Expected output (yours will differ):

```
fastapi           0.115.0
numpy             2.1.1
pandas            2.2.2
scikit-learn      1.5.1
```

---

## Step 4: Generate a reproducible synthetic incident dataset

We do not have a real incident feed, so we simulate one. The key is `np.random.seed(42)` at the top, which makes the "random" data the same every time you run it. That is what makes your numbers match this guide.

The story behind the data: a security team logs incidents. Each incident has a **category** (phishing, malware, policy violation, and so on) and a few numeric signals. Some categories and signals genuinely make an incident more severe. We bake that relationship in, then let the model rediscover it.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi generate_data.py
```

Press `i` to enter insert mode, then type this in:

```python
import numpy as np
import pandas as pd

np.random.seed(42)          # makes the dataset identical every run

N = 900                     # small on purpose - runs fast on a t3 box

# Categorical feature: what kind of incident it is.
categories = ["phishing", "malware", "policy_violation",
              "unauthorized_access", "data_exfiltration", "spam"]
# Weights so the mix looks realistic (spam and phishing are common,
# data exfiltration is rare).
cat_probs = [0.28, 0.18, 0.15, 0.14, 0.07, 0.18]
category = np.random.choice(categories, size=N, p=cat_probs)

# Numeric signals an analyst might see:
# assets_affected: how many machines/accounts are involved (1..50)
assets_affected = np.random.randint(1, 51, size=N)
# failed_logins: burst of failed logins around the event (0..200)
failed_logins = np.random.poisson(lam=8, size=N).clip(0, 200)
# data_volume_mb: how much data moved during the event
data_volume_mb = np.random.exponential(scale=50, size=N).round(1).clip(0, None)
# off_hours: 1 if it happened outside business hours, else 0
off_hours = np.random.binomial(1, 0.35, size=N)
# external_source: 1 if traffic came from outside the network
external_source = np.random.binomial(1, 0.5, size=N)

# Build a hidden "severity score" from the signals. This is the true
# relationship we want the model to learn. Some categories are inherently
# more dangerous.
cat_risk = {
    "phishing": 1.0, "malware": 2.0, "policy_violation": 0.5,
    "unauthorized_access": 2.2, "data_exfiltration": 3.5, "spam": 0.1,
}
base = np.array([cat_risk[c] for c in category])

score = (
    base
    + 0.05 * assets_affected
    + 0.010 * failed_logins
    + 0.015 * data_volume_mb
    + 0.6 * off_hours
    + 0.5 * external_source
    + np.random.normal(0, 0.6, size=N)   # noise so it is not perfectly separable
)

# Turn the continuous score into 3 priority labels using cut points.
# low = 0, medium = 1, high = 2.
priority = np.where(score < 2.2, "low",
             np.where(score < 3.6, "medium", "high"))

df = pd.DataFrame({
    "category": category,
    "assets_affected": assets_affected,
    "failed_logins": failed_logins,
    "data_volume_mb": data_volume_mb,
    "off_hours": off_hours,
    "external_source": external_source,
    "priority": priority,
})

df.to_csv("incidents.csv", index=False)
print("Wrote incidents.csv with", len(df), "rows")
print(df["priority"].value_counts())
```

Press `Esc`, type `:wq`, and press Enter. `:wq` means "write (save) and quit" in vi.

Run it:

```bash
python generate_data.py
```

Expected output (yours will differ):

```
Wrote incidents.csv with 900 rows
priority
medium    402
low       333
high      165
```

Read the class counts. `medium` is the most common and `high` is the rarest. That imbalance matters later - a model can look accurate just by ignoring the rare `high` class, which is exactly the class the security team cares about most.

---

## Step 5: Explore the data before modelling

Never model data you have not looked at. This step is straight from the ML lifecycle (Concepts 4.1, "understand your data").

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi explore.py
```

Press `i` and enter:

```python
import pandas as pd

df = pd.read_csv("incidents.csv")

print("Shape (rows, columns):", df.shape)
print()
print("First 3 rows:")
print(df.head(3))
print()
print("Any missing values?")
print(df.isna().sum())
print()
print("Average failed_logins by priority:")
print(df.groupby("priority")["failed_logins"].mean().round(2))
print()
print("Priority mix within each category:")
print(pd.crosstab(df["category"], df["priority"]))
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python explore.py
```

Expected output (yours will differ):

```
Shape (rows, columns): (900, 7)

First 3 rows:
      category  assets_affected  failed_logins  data_volume_mb  off_hours  external_source priority
0  policy_violation             34              6            18.4          0                1      low
1     data_exfiltration          9             11            72.1          1                1     high
2          phishing            21              7            40.5          0                0   medium

Any missing values?
category           0
assets_affected    0
failed_logins      0
data_volume_mb     0
off_hours          0
external_source    0
priority           0
dtype: int64

Average failed_logins by priority:
priority
high      9.41
low       7.02
medium    8.03
...
```

Two useful facts jump out. There are no missing values (nice, real data is rarely this clean). And higher-priority incidents tend to have more failed logins - a sign the model has real signal to learn.

---

## Step 6: Split the data into train and test sets

We must judge the model on data it has never seen. We split off 25 percent as a test set and stratify by `priority` so the rare `high` class appears in both halves in the same proportion.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi split.py
```

Press `i` and enter:

```python
import pandas as pd
from sklearn.model_selection import train_test_split

df = pd.read_csv("incidents.csv")

X = df.drop(columns=["priority"])   # features: everything except the label
y = df["priority"]                  # label: what we want to predict

X_train, X_test, y_train, y_test = train_test_split(
    X, y,
    test_size=0.25,        # 25 percent held out for honest testing
    random_state=42,       # reproducible split
    stratify=y,            # keep class proportions equal in both halves
)

print("Train rows:", len(X_train), " Test rows:", len(X_test))
print("Train priority mix:")
print(y_train.value_counts(normalize=True).round(3))
print("Test priority mix:")
print(y_test.value_counts(normalize=True).round(3))
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python split.py
```

Expected output (yours will differ):

```
Train rows: 675  Test rows: 225
Train priority mix:
priority
medium    0.447
low       0.370
high      0.183
Name: proportion, dtype: float64
Test priority mix:
priority
medium    0.444
low       0.369
high      0.187
Name: proportion, dtype: float64
```

The two mixes match almost exactly. That is `stratify=y` doing its job. If we had not stratified, the small `high` class could have landed mostly in one half by luck and thrown off the whole evaluation.

---

## Step 7: Train and compare three models

Now the main event. We build one preprocessing pipeline (one-hot encode the `category` text column, scale the numeric columns) and reuse it for three different models: logistic regression, random forest, and gradient boosting (all covered in Concepts 4.2). We compare them on the same test set so the comparison is fair.

We scale numeric features because logistic regression cares about scale. Tree models (random forest, gradient boosting) do not care about scaling, but running everything through the same pipeline keeps the code simple and does no harm.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi train_compare.py
```

Press `i` and enter:

```python
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.metrics import accuracy_score, f1_score

df = pd.read_csv("incidents.csv")
X = df.drop(columns=["priority"])
y = df["priority"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

# Which columns are text (categorical) and which are numbers.
categorical = ["category"]
numeric = ["assets_affected", "failed_logins", "data_volume_mb",
           "off_hours", "external_source"]

# Preprocessing: one-hot the category, scale the numbers.
# handle_unknown="ignore" means a never-seen category at prediction time
# becomes all-zeros instead of crashing.
preprocess = ColumnTransformer([
    ("cat", OneHotEncoder(handle_unknown="ignore"), categorical),
    ("num", StandardScaler(), numeric),
])

# The three models we compare. class_weight="balanced" tells the linear and
# forest models to pay extra attention to the rare "high" class.
models = {
    "logistic_regression": LogisticRegression(
        max_iter=1000, class_weight="balanced", random_state=42),
    "random_forest": RandomForestClassifier(
        n_estimators=200, class_weight="balanced", random_state=42),
    "gradient_boosting": GradientBoostingClassifier(random_state=42),
}

print(f"{'model':<22}{'accuracy':>10}{'macro_f1':>10}")
print("-" * 42)
for name, model in models.items():
    pipe = Pipeline([("prep", preprocess), ("model", model)])
    pipe.fit(X_train, y_train)                 # learn from training data
    preds = pipe.predict(X_test)               # predict on unseen test data
    acc = accuracy_score(y_test, preds)
    # macro_f1 averages F1 across all 3 classes EQUALLY, so the rare "high"
    # class counts as much as the common ones. This is the metric we trust
    # more than plain accuracy on imbalanced data (Concepts 4.5).
    mf1 = f1_score(y_test, preds, average="macro")
    print(f"{name:<22}{acc:>10.3f}{mf1:>10.3f}")
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python train_compare.py
```

Expected output (yours will differ):

```
model                   accuracy  macro_f1
------------------------------------------
logistic_regression        0.813     0.804
random_forest              0.849     0.833
gradient_boosting          0.858     0.841
```

Read the table. All three are in the low-to-mid 80s. Gradient boosting edges out the others on both accuracy and macro-F1, with random forest close behind. Logistic regression is the simplest and most explainable but trails a little. We will pick the winner in Step 11 after we also weigh explainability and error risk, not accuracy alone.

Notice we compare on **macro-F1**, not just accuracy. A model that ignored the rare `high` class would still score decent accuracy but a poor macro-F1. Macro-F1 keeps us honest about the class we care about most.

---

## Step 8: Look at the full per-class report and confusion matrix

The single accuracy number hides where the model is right and wrong. The confusion matrix and classification report (Concepts 4.5) show the truth per class. We run them for the strongest model, gradient boosting.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi report.py
```

Press `i` and enter:

```python
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import classification_report, confusion_matrix

df = pd.read_csv("incidents.csv")
X = df.drop(columns=["priority"])
y = df["priority"]
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

categorical = ["category"]
numeric = ["assets_affected", "failed_logins", "data_volume_mb",
           "off_hours", "external_source"]
preprocess = ColumnTransformer([
    ("cat", OneHotEncoder(handle_unknown="ignore"), categorical),
    ("num", StandardScaler(), numeric),
])

pipe = Pipeline([
    ("prep", preprocess),
    ("model", GradientBoostingClassifier(random_state=42)),
])
pipe.fit(X_train, y_train)
preds = pipe.predict(X_test)

labels = ["low", "medium", "high"]   # fixed order so the matrix is readable
print("Confusion matrix (rows = true, columns = predicted):")
print("labels order:", labels)
print(confusion_matrix(y_test, preds, labels=labels))
print()
print(classification_report(y_test, preds, labels=labels, digits=3))
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python report.py
```

Expected output (yours will differ):

```
Confusion matrix (rows = true, columns = predicted):
labels order: ['low', 'medium', 'high']
[[76  7  0]
 [ 9 85  6]
 [ 0  9 33]]

              precision    recall  f1-score   support

         low      0.894     0.916     0.905        83
      medium      0.842     0.850     0.846       100
        high      0.846     0.786     0.815        42

    accuracy                          0.858       225
   macro avg      0.861     0.851     0.855       225
weighted avg      0.858     0.858     0.858       225
```

How to read the confusion matrix: each row is the true priority, each column is what the model predicted. The diagonal (76, 85, 33) is correct predictions. Off-diagonal cells are mistakes. For example, the bottom row shows 9 real `high` incidents were predicted as `medium` - those are dangerous misses, because a real high-priority incident got downgraded. The `recall` for `high` (0.786) tells you the model catches about 79 percent of true high incidents. We will treat that miss rate as the headline risk in the model card.

---

## Step 9: Explain which features drive the predictions

A model the client cannot understand is a model the client will not trust. Tree models expose `feature_importances_`, which ranks how much each feature contributed. We map those back to human-readable names.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi importance.py
```

Press `i` and enter:

```python
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.ensemble import GradientBoostingClassifier

df = pd.read_csv("incidents.csv")
X = df.drop(columns=["priority"])
y = df["priority"]
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

categorical = ["category"]
numeric = ["assets_affected", "failed_logins", "data_volume_mb",
           "off_hours", "external_source"]
preprocess = ColumnTransformer([
    ("cat", OneHotEncoder(handle_unknown="ignore"), categorical),
    ("num", StandardScaler(), numeric),
])
pipe = Pipeline([
    ("prep", preprocess),
    ("model", GradientBoostingClassifier(random_state=42)),
])
pipe.fit(X_train, y_train)

# Pull the human-readable feature names out of the fitted preprocessor.
feature_names = pipe.named_steps["prep"].get_feature_names_out()
importances = pipe.named_steps["model"].feature_importances_

ranking = (pd.Series(importances, index=feature_names)
           .sort_values(ascending=False)
           .round(3))

print("Feature importance (higher = more influence on predictions):")
print(ranking.head(10))
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python importance.py
```

Expected output (yours will differ):

```
Feature importance (higher = more influence on predictions):
num__data_volume_mb            0.271
num__failed_logins             0.198
num__assets_affected           0.164
cat__category_data_exfiltration 0.121
num__off_hours                 0.088
cat__category_malware          0.061
num__external_source           0.049
cat__category_unauthorized_access 0.031
cat__category_phishing         0.010
cat__category_spam             0.004
```

This is a story you can tell a client in one sentence: "The model weighs how much data moved, how many failed logins occurred, and how many assets were affected the most, and it treats data-exfiltration incidents as inherently risky." That matches how a human analyst thinks, which is a good sanity check that the model learned something sensible and not an accident.

A word of caution from Concepts 4.6: feature importance shows what the model USES, not what CAUSES severity. Do not present it as proof of causation.

---

## Step 10: Measure false-positive and false-negative risk

For a priority model, the two errors are not equal. Downgrading a real `high` incident (a false negative on the high class) can mean a breach goes unhandled. Upgrading a `low` incident (a false positive on the high class) just wastes an analyst's time. We quantify both so the client can decide what they can live with.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi error_analysis.py
```

Press `i` and enter:

```python
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.ensemble import GradientBoostingClassifier

df = pd.read_csv("incidents.csv")
X = df.drop(columns=["priority"])
y = df["priority"]
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

categorical = ["category"]
numeric = ["assets_affected", "failed_logins", "data_volume_mb",
           "off_hours", "external_source"]
preprocess = ColumnTransformer([
    ("cat", OneHotEncoder(handle_unknown="ignore"), categorical),
    ("num", StandardScaler(), numeric),
])
pipe = Pipeline([
    ("prep", preprocess),
    ("model", GradientBoostingClassifier(random_state=42)),
])
pipe.fit(X_train, y_train)
preds = pipe.predict(X_test)

results = pd.DataFrame({"true": y_test.values, "pred": preds})

# Dangerous misses: a real "high" that we called something lower.
missed_high = results[(results["true"] == "high") & (results["pred"] != "high")]
# Wasted effort: something not "high" that we escalated to "high".
false_high = results[(results["true"] != "high") & (results["pred"] == "high")]

total_high = (results["true"] == "high").sum()
print("Total true HIGH incidents in test set:", total_high)
print("Dangerous MISSES (real high downgraded):", len(missed_high),
      f"= {len(missed_high)/total_high:.1%} of highs missed")
print("Wasted ESCALATIONS (non-high called high):", len(false_high))
print()
print("What the missed highs were downgraded to:")
print(missed_high["pred"].value_counts())
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python error_analysis.py
```

Expected output (yours will differ):

```
Total true HIGH incidents in test set: 42
Dangerous MISSES (real high downgraded): 9 = 21.4% of highs missed
Wasted ESCALATIONS (non-high called high): 6

What the missed highs were downgraded to:
medium    9
```

This is the honest headline for the client: the model misses about 1 in 5 truly high-priority incidents, and every miss is downgraded to `medium` (not all the way to `low`, which is a small comfort). If missing a high incident is unacceptable, that is a reason to lower the decision threshold for the high class or keep a human reviewing every `medium`. You will practice that tradeoff in the USE exercise on threshold tuning.

---

## Step 11: Pick the winner and write the model card

You now have everything to choose. Gradient boosting had the best accuracy and macro-F1, random forest was close and also gives clean feature importances, logistic regression was the most explainable but weakest. We pick **gradient boosting** as the primary model and note random forest as the explainable fallback. A model card (Concepts 4.6) is a short honesty document that ships with the model so nobody has to guess what it does or where it breaks.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi model_card.md
```

Press `i` and enter:

```markdown
# Model Card: Incident-Priority Classifier v1

## What it does
Predicts a security incident's priority (low / medium / high) from its
category and a few numeric signals (assets affected, failed logins, data
volume, off-hours flag, external-source flag). It is a triage aid to help a
security team decide what to work on first.

## Intended use
Decision SUPPORT for human analysts. It is NOT an autonomous system. A human
reviews and can override every prediction.

## Training data
900 synthetic incidents generated with a fixed seed (see generate_data.py).
Class mix: medium ~45%, low ~37%, high ~18%. Synthetic data does not capture
real attacker behavior; retrain on real logged incidents before production.

## Model
Gradient boosting classifier (scikit-learn), chosen over random forest and
logistic regression on macro-F1. Random forest is the explainable fallback.

## Performance (held-out test set, 225 incidents)
- Accuracy: ~0.86
- Macro-F1: ~0.84
- Recall on the HIGH class: ~0.79 (it misses about 1 in 5 true highs)

## Known risks
- FALSE NEGATIVE (worst case): a real HIGH incident downgraded to MEDIUM.
  About 21% of true highs are missed in testing. This can delay response to a
  serious incident. Mitigation: humans review all MEDIUM and HIGH; consider a
  lower threshold for the HIGH class.
- FALSE POSITIVE: a non-high incident escalated to HIGH. Wastes analyst time
  but is not dangerous.
- Feature importance shows correlation, not causation. Do not use it to claim
  a cause of severity.
- Trained on synthetic data. Real distributions will differ (dataset shift).

## Monitoring
Track recall on the HIGH class weekly against a labeled sample. If it drops,
suspect concept drift (Concepts 4.6) and retrain.

## Owner and version
Owner: [SECURITY DATA TEAM]. Version: v1. Retrain cadence: quarterly or on
drift alert.
```

Press `Esc`, type `:wq`, press Enter.

You do not run a markdown file. Confirm it saved:

```bash
head -5 model_card.md
```

`head -5` prints the first 5 lines of the file.

Expected output:

```
# Model Card: Incident-Priority Classifier v1

## What it does
Predicts a security incident's priority (low / medium / high) from its
category and a few numeric signals (assets affected, failed logins, data
```

---

## Step 12: Train the winner and save it to disk

To serve predictions we train the chosen model once and save the whole pipeline (preprocessing plus model) to a file with `joblib`. Saving the pipeline, not just the model, means the exact same encoding and scaling get applied at prediction time.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi save_model.py
```

Press `i` and enter:

```python
import pandas as pd
import joblib
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.ensemble import GradientBoostingClassifier

df = pd.read_csv("incidents.csv")
X = df.drop(columns=["priority"])
y = df["priority"]
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

categorical = ["category"]
numeric = ["assets_affected", "failed_logins", "data_volume_mb",
           "off_hours", "external_source"]
preprocess = ColumnTransformer([
    ("cat", OneHotEncoder(handle_unknown="ignore"), categorical),
    ("num", StandardScaler(), numeric),
])
pipe = Pipeline([
    ("prep", preprocess),
    ("model", GradientBoostingClassifier(random_state=42)),
])
pipe.fit(X_train, y_train)

joblib.dump(pipe, "incident_model.joblib")   # save the whole pipeline
print("Saved incident_model.joblib")
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python save_model.py
```

Expected output:

```
Saved incident_model.joblib
```

Confirm the file exists:

```bash
ls -lh incident_model.joblib
```

`ls -lh` lists the file with a human-readable (`-h`) size in long (`-l`) format.

Expected output (yours will differ):

```
-rw-rw-r--. 1 ec2-user ec2-user 253K Jul 25 14:10 incident_model.joblib
```

---

## Step 13: Write the FastAPI prediction endpoint

Now we expose the model over HTTP so any application could ask for a priority. FastAPI uses a Pydantic model to validate the incoming JSON, so a malformed request is rejected with a clear error instead of crashing the server.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi serve.py
```

Press `i` and enter:

```python
import pandas as pd
import joblib
from fastapi import FastAPI
from pydantic import BaseModel

# Load the saved pipeline once, when the server starts.
model = joblib.load("incident_model.joblib")

app = FastAPI(title="Incident Priority API")

# Describes and validates the JSON body of a prediction request.
class Incident(BaseModel):
    category: str
    assets_affected: int
    failed_logins: int
    data_volume_mb: float
    off_hours: int
    external_source: int

@app.get("/health")
def health():
    # A simple liveness check so ops can confirm the service is up.
    return {"status": "ok"}

@app.post("/predict")
def predict(incident: Incident):
    # Turn the request into a one-row DataFrame with the same columns the
    # model was trained on.
    row = pd.DataFrame([incident.model_dump()])
    priority = model.predict(row)[0]
    # predict_proba gives a confidence per class; we return the top one.
    proba = model.predict_proba(row)[0]
    classes = list(model.classes_)
    confidence = float(max(proba))
    return {
        "priority": str(priority),
        "confidence": round(confidence, 3),
        "scores": {c: round(float(p), 3) for c, p in zip(classes, proba)},
    }
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 14: Start the API server

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
uvicorn serve:app --host 127.0.0.1 --port 8000
```

What this does: `uvicorn` runs the app object named `app` inside `serve.py`. `--host 127.0.0.1` binds to localhost only (safe for this lab). `--port 8000` is the port to listen on.

Expected output (yours will differ):

```
INFO:     Started server process [12873]
INFO:     Waiting for application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

Leave this terminal running the server. We will call it from a second terminal in the next step.

---

## Step 15: Call the endpoint from a second terminal

Open a second connection to the lab server. SSH into your **lab server** again in a new terminal window, as **ec2-user**.

First a quick health check with `curl`. `curl` is a command-line HTTP client. The URL points at the running server:

```bash
curl -s http://127.0.0.1:8000/health
```

`-s` means "silent" (no progress bar).

Expected output:

```
{"status":"ok"}
```

Now send a real incident to `/predict`. This one is a serious data-exfiltration event: lots of data moved, many assets, off-hours, external source. We expect a `high` priority.

```bash
curl -s -X POST http://127.0.0.1:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"category":"data_exfiltration","assets_affected":40,"failed_logins":25,"data_volume_mb":320.5,"off_hours":1,"external_source":1}'
```

What the flags do: `-X POST` sends a POST request. `-H` sets a header saying the body is JSON. `-d` is the JSON body (the incident).

Expected output (yours will differ slightly):

```
{"priority":"high","confidence":0.912,"scores":{"high":0.912,"low":0.014,"medium":0.074}}
```

Now send a harmless one - a small spam report during business hours. We expect `low`:

```bash
curl -s -X POST http://127.0.0.1:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"category":"spam","assets_affected":1,"failed_logins":0,"data_volume_mb":2.0,"off_hours":0,"external_source":0}'
```

Expected output (yours will differ slightly):

```
{"priority":"low","confidence":0.869,"scores":{"high":0.008,"low":0.869,"medium":0.123}}
```

The model returns not just a label but a confidence and per-class scores, so a downstream system (or a human) can decide how much to trust each call. That is exactly what the model card promised: decision support, with the numbers exposed.

---

## Step 16: Stop the server and deactivate

Switch back to your **first terminal** (the one running uvicorn). Press `Ctrl+C` to stop the server.

Expected output:

```
INFO:     Shutting down
INFO:     Application shutdown complete.
INFO:     Finished server process [12873]
```

When you are done working, leave the virtual environment. `deactivate` is a function the venv added to your shell:

```bash
deactivate
```

Your prompt no longer shows `(.venv)`.

---

## What you built

You took a problem from "we are drowning in incidents" to a working, honest ML system:

1. Framed the problem and generated reproducible data (lifecycle, Concepts 4.1).
2. Explored and split the data with stratification (feature engineering + evaluation).
3. Trained and fairly compared logistic regression, random forest, and gradient boosting.
4. Read the confusion matrix and per-class recall instead of trusting accuracy alone.
5. Explained the model with feature importance, and flagged correlation-not-causation.
6. Quantified the real business risk - the ~21 percent of high incidents it misses.
7. Wrote a model card so nobody deploys it blind.
8. Saved the pipeline and served live predictions over FastAPI.

That end-to-end honesty - especially the model card and the false-negative analysis - is what separates a consultant from someone who just calls `.fit()`. Next, in the USE phase, you will re-tune the decision threshold to trade precision for recall and justify the call to a stakeholder, and in SURVIVE you will hunt down data leakage, class imbalance, and concept drift in models that look fine but are not.
