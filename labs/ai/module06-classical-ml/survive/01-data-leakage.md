# SURVIVE 01: Data Leakage - The Model That Cheated

Your model gets 99.8% accuracy on the test set. It seems perfect. But in production, it performs no better than random guessing. The model cheated during testing.

---

## The Scenario

A junior data scientist built a model to predict server incidents. They normalized the data BEFORE splitting into train/test. This leaked information from the test set into the training process.

---

## Step 1. See the inflated accuracy

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, f1_score

np.random.seed(42)
n = 300
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)
incident = ((cpu > 70) & (connections > 180) | ((cpu > 85) & (memory > 80))).astype(int)
noise = np.random.random(n) < 0.05
incident[noise] = 1 - incident[noise]

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'memory_percent': memory, 'incident': incident,
})

X = df.drop('incident', axis=1)
y = df['incident']

# ============================================
# BUG: Normalize BEFORE splitting (data leakage!)
# ============================================
scaler = StandardScaler()
X_normalized = pd.DataFrame(
    scaler.fit_transform(X),  # fit_transform on ALL data
    columns=X.columns
)
# This calculated mean and std from ALL 300 rows
# Including the 60 rows that will become the test set!

X_train, X_test, y_train, y_test = train_test_split(
    X_normalized, y, test_size=0.2, random_state=42
)

model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X_train, y_train)
predictions = model.predict(X_test)

acc = accuracy_score(y_test, predictions)
f1 = f1_score(y_test, predictions)

print("=== LEAKY MODEL (normalized before splitting) ===")
print(f"Accuracy: {acc:.1%}")
print(f"F1 Score: {f1:.3f}")
print()

# Now simulate production: new data with slightly different distribution
np.random.seed(99)
n_prod = 100
cpu_prod = np.random.uniform(15, 90, n_prod)  # slightly different range
conn_prod = np.random.uniform(10, 280, n_prod)
mem_prod = np.random.uniform(25, 90, n_prod)
inc_prod = ((cpu_prod > 70) & (conn_prod > 180) | ((cpu_prod > 85) & (mem_prod > 80))).astype(int)

X_prod = pd.DataFrame({
    'cpu_percent': cpu_prod, 'connections': conn_prod, 'memory_percent': mem_prod,
})

# Normalize production data with the SAME scaler (which was fit on all training+test data)
X_prod_scaled = pd.DataFrame(scaler.transform(X_prod), columns=X.columns)

prod_predictions = model.predict(X_prod_scaled)
prod_acc = accuracy_score(inc_prod, prod_predictions)
prod_f1 = f1_score(inc_prod, prod_predictions)

print("=== PRODUCTION PERFORMANCE ===")
print(f"Accuracy: {prod_acc:.1%}")
print(f"F1 Score: {prod_f1:.3f}")
print()
print(f"Test accuracy: {acc:.1%} vs Production accuracy: {prod_acc:.1%}")
print(f"Gap: {(acc - prod_acc)*100:.1f} percentage points!")
print()
print("The model looked great on the test set but is worse in production.")
print("Why? The test set was contaminated during normalization.")
PYEOF
```

Expected output (yours will differ):
```
=== LEAKY MODEL (normalized before splitting) ===
Accuracy: 96.7%
F1 Score: 0.923

=== PRODUCTION PERFORMANCE ===
Accuracy: 89.0%
F1 Score: 0.750

Test accuracy: 96.7% vs Production accuracy: 89.0%
Gap: 7.7 percentage points!

The model looked great on the test set but is worse in production.
Why? The test set was contaminated during normalization.
```

---

## Step 2. Understand the leak

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
What went wrong?

WRONG ORDER (data leakage):
  1. Load all 300 rows
  2. Normalize ALL 300 rows  <- BUG! Calculates mean/std from ALL data
  3. Split into train (240) and test (60)
  4. Train on 240 normalized rows
  5. Test on 60 normalized rows

The test set's mean and std were used to normalize the training set.
Information from the test set "leaked" into the training process.

It's like a teacher grading a test... after telling students the answer key.
The test scores look great, but students didn't actually learn.

CORRECT ORDER:
  1. Load all 300 rows
  2. Split into train (240) and test (60)  <- SPLIT FIRST
  3. Normalize train set (fit + transform)
  4. Normalize test set (transform only, using train's mean/std)
  5. Train on normalized training data
  6. Test on normalized test data

The key rule: fit on train, transform on test.
Never let the test data influence any preprocessing step.
""")
PYEOF
```

---

## Step 3. Fix the leak

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, f1_score

np.random.seed(42)
n = 300
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)
incident = ((cpu > 70) & (connections > 180) | ((cpu > 85) & (memory > 80))).astype(int)
noise = np.random.random(n) < 0.05
incident[noise] = 1 - incident[noise]

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'memory_percent': memory, 'incident': incident,
})

X = df.drop('incident', axis=1)
y = df['incident']

# ============================================
# FIX: Split FIRST, then normalize
# ============================================
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

scaler = StandardScaler()

# fit_transform on TRAINING data only
# This calculates mean and std from training data ONLY
X_train_scaled = scaler.fit_transform(X_train)

# transform (NOT fit_transform!) on test data
# Uses the mean and std from training - no leakage
X_test_scaled = scaler.transform(X_test)

model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X_train_scaled, y_train)
predictions = model.predict(X_test_scaled)

acc = accuracy_score(y_test, predictions)
f1 = f1_score(y_test, predictions)

print("=== FIXED MODEL (split first, then normalize) ===")
print(f"Test Accuracy: {acc:.1%}")
print(f"Test F1 Score: {f1:.3f}")
print()

# Now test on production data
np.random.seed(99)
n_prod = 100
cpu_prod = np.random.uniform(15, 90, n_prod)
conn_prod = np.random.uniform(10, 280, n_prod)
mem_prod = np.random.uniform(25, 90, n_prod)
inc_prod = ((cpu_prod > 70) & (conn_prod > 180) | ((cpu_prod > 85) & (mem_prod > 80))).astype(int)

X_prod = pd.DataFrame({
    'cpu_percent': cpu_prod, 'connections': conn_prod, 'memory_percent': mem_prod,
})

# Use same scaler (fit on training data only)
X_prod_scaled = scaler.transform(X_prod)
prod_predictions = model.predict(X_prod_scaled)
prod_acc = accuracy_score(inc_prod, prod_predictions)
prod_f1 = f1_score(inc_prod, prod_predictions)

print("=== PRODUCTION PERFORMANCE ===")
print(f"Production Accuracy: {prod_acc:.1%}")
print(f"Production F1 Score: {prod_f1:.3f}")
print()
print(f"Test vs Production gap: {abs(acc - prod_acc)*100:.1f} percentage points")
print()
print("The gap is much smaller now - the test score is honest.")
print()
print("THE RULE:")
print("  1. Split FIRST")
print("  2. fit_transform() on training data")
print("  3. transform() on test/production data")
print("  NEVER fit on test data. NEVER fit on all data before splitting.")
PYEOF
```

Expected output (yours will differ):
```
=== FIXED MODEL (split first, then normalize) ===
Test Accuracy: 95.0%
Test F1 Score: 0.880

=== PRODUCTION PERFORMANCE ===
Production Accuracy: 91.0%
Production F1 Score: 0.778

Test vs Production gap: 4.0 percentage points

The gap is much smaller now - the test score is honest.

THE RULE:
  1. Split FIRST
  2. fit_transform() on training data
  3. transform() on test/production data
  NEVER fit on test data. NEVER fit on all data before splitting.
```

---

## What You Learned

| Problem | Wrong Way | Right Way |
|---------|----------|-----------|
| Normalization | Normalize ALL data, then split | Split first, normalize each set |
| Scaler fitting | `scaler.fit_transform(all_data)` | `scaler.fit_transform(train)` then `scaler.transform(test)` |
| Feature engineering | Create features using all data | Create features using training data only |
| Why it matters | Test accuracy is fake (too high) | Test accuracy reflects real production performance |

**Data leakage = any information from the test/production data that influences training or preprocessing.**
