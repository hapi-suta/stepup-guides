# SURVIVE 01: The Corrupted Dataset

## Scenario

You're building an AI model to predict slow database queries. Your teammate sent you the training dataset, but something is wrong - the model's accuracy is terrible (52%, basically a coin flip). Your job: find and fix the data problems.

> **Note:** This scenario uses sklearn (machine learning library) which you'll learn in Module 6.
> You don't need to understand the ML parts yet. Focus on the DATA problems - that's the DBA skill here.
> The pandas commands (finding nulls, duplicates, wrong types) are what matter in this exercise.

---

## The Broken Code

Save this to a file and run it:

```bash
cat > /tmp/survive_corrupted.py << 'PYEOF'
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split    # splits data into training/testing sets
from sklearn.ensemble import RandomForestClassifier     # a machine learning model (Module 6)
from sklearn.metrics import accuracy_score              # measures how often the model is correct

np.random.seed(42)
n = 1000

# Generate "training data"
data = {
    'cpu_percent': np.concatenate([
        np.random.normal(45, 15, 800),     # normal ops
        np.random.normal(90, 5, 200),       # high load
    ]),
    'active_connections': np.concatenate([
        np.random.normal(50, 20, 800),
        np.random.normal(200, 30, 200),
    ]),
    'rows_scanned': np.concatenate([
        np.random.exponential(1000, 800),
        np.random.exponential(50000, 200),
    ]),
    'query_time_ms': np.concatenate([
        np.random.normal(30, 10, 800),
        np.random.normal(500, 100, 200),
    ]),
}
df = pd.DataFrame(data)
df['is_slow'] = (df['query_time_ms'] > 200).astype(int)

# === BUG 1: Injected data corruption ===
# 15% of rows have cpu_percent set to -999 (sensor error)
corrupt_idx = np.random.choice(n, size=150, replace=False)
df.loc[corrupt_idx, 'cpu_percent'] = -999

# === BUG 2: Duplicate rows ===
# 200 rows are exact duplicates (copy-paste error during data collection)
dupes = df.sample(200, random_state=42)
df = pd.concat([df, dupes], ignore_index=True)

# === BUG 3: Label leakage ===
# query_time_ms is used as a feature BUT it's also what we derived the label from
# The model will just learn "if query_time_ms > 200 then slow" - no real learning

# === BUG 4: String contamination ===
# Some rows have "N/A" in active_connections (someone exported from Excel)
str_idx = np.random.choice(len(df), size=50, replace=False)
df['active_connections'] = df['active_connections'].astype(object)
df.loc[str_idx, 'active_connections'] = 'N/A'

# Train the model
features = ['cpu_percent', 'active_connections', 'rows_scanned', 'query_time_ms']
X = df[features]
y = df['is_slow']

try:
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    preds = model.predict(X_test)
    acc = accuracy_score(y_test, preds)
    print(f'Model accuracy: {acc:.2%}')
except Exception as e:
    print(f'ERROR: {e}')

print(f'Dataset shape: {df.shape}')
print(f'Label distribution:\n{df["is_slow"].value_counts()}')
PYEOF
python3 /tmp/survive_corrupted.py
```

Expected output:
```
ERROR: could not convert string to float: 'N/A'
Dataset shape: (1200, 6)
...
```

---

## Your Mission

Fix ALL 4 bugs in the dataset so the model trains successfully with >90% accuracy. The bugs are:

1. **Corrupted values** - Some cpu_percent values are -999 (impossible)
2. **Duplicate rows** - Dataset has 1200 rows but should have 1000
3. **Data leakage** - One of the features IS the answer (this is the sneaky one)
4. **Type contamination** - Some numeric columns contain strings

**Rules:**
- Don't change the model (RandomForestClassifier) or its parameters
- Only fix the data
- You must print the accuracy after fixing

---

## Diagnostic Steps

Before fixing anything, investigate:

```python
# Check for obvious problems
print(df.info())
print(df.describe())
print(df[df['cpu_percent'] < 0])
print(df.duplicated().sum())
```

---

## Validation

After your fix, run:

```bash
python3 /tmp/survive_fixed.py
```

A successful fix produces:
```
Model accuracy: >90%
Dataset shape: (should be ~850-1000 rows)
No -999 values in cpu_percent
No duplicate rows
No string values in numeric columns
query_time_ms NOT in features list
```

<details>
<summary>Runbook (hints, not answers)</summary>

1. **Find the -999 values.** How would you find NULL sensors in a monitoring table? Same approach - filter and either remove or replace.

2. **Remove duplicates.** Pandas has a one-liner for this. Think: `SELECT DISTINCT`.

3. **Data leakage is the hardest bug.** Look at your features list. One of them is `query_time_ms`. Your label `is_slow` was derived FROM `query_time_ms > 200`. If you give the model `query_time_ms` as input, it already has the answer. Remove it from features.

4. **String contamination.** `pd.to_numeric()` with `errors='coerce'` converts strings to NaN, then you can fill or drop them.
</details>
