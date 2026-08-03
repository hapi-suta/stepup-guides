# Build 01: The ML Workflow + Linear Regression

Every machine learning project follows the same 6 steps. You'll learn them by building a model that predicts query time from server metrics.

---

## Step 1. Load and explore data

Before building any model, look at your data. This is like running `\d` and `SELECT count(*)` before writing a query.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd

# pandas is a library for working with tables (like SQL result sets)
# pd is the short name, like np for numpy

# --- Create training data ---
# Simulating server metrics and their corresponding query times
# In production, you'd pull this from pg_stat_statements or monitoring

np.random.seed(42)  # makes random numbers repeatable

# Generate 100 data points
n = 100

# Features (what we know - the inputs)
cpu = np.random.uniform(10, 95, n)           # CPU % (10-95)
connections = np.random.uniform(5, 290, n)   # Active connections (5-290)
table_size_gb = np.random.uniform(0.1, 50, n) # Table size in GB

# Label (what we're predicting - the output)
# Query time depends on all three features + some randomness
# This is the "hidden rule" the model needs to discover
query_time_ms = (
    0.5 * cpu +              # higher CPU = slower queries
    0.1 * connections +      # more connections = slower
    2.0 * table_size_gb +   # bigger tables = much slower
    np.random.normal(0, 5, n)  # random noise (real data is messy)
)

# Put it all in a DataFrame (a table - like a SQL result set)
# pd.DataFrame() creates a table from a dictionary
# Keys become column names, values become column data
df = pd.DataFrame({
    'cpu_percent': cpu,
    'connections': connections,
    'table_size_gb': table_size_gb,
    'query_time_ms': query_time_ms,
})

# --- Explore the data ---
# .shape tells you (rows, columns) - like SELECT count(*) and counting columns
print(f"Data shape: {df.shape[0]} rows, {df.shape[1]} columns")
print()

# .head() shows the first 5 rows - like SELECT * LIMIT 5
print("First 5 rows:")
print(df.head().to_string(index=False))
print()

# .describe() gives statistics for each column
# Like running avg(), min(), max(), stddev() on every column
print("Statistics:")
print(df.describe().round(2).to_string())
print()

# Check for missing values (NaN) - like checking for NULLs
# .isnull().sum() counts NULLs per column
print("Missing values per column:")
print(df.isnull().sum().to_string())
PYEOF
```

Expected output (yours will differ):
```
Data shape: 100 rows, 4 columns

First 5 rows:
 cpu_percent  connections  table_size_gb  query_time_ms
   47.156704    97.832036      36.235637     106.213928
   82.706914   176.645498      22.455864      77.652716
   90.051104   201.755699       5.798867      72.414587
   97.266873    50.519019      13.700987      84.002651
   31.028719    73.730978      41.247587     117.127203

Statistics:
       cpu_percent  connections  table_size_gb  query_time_ms
count       100.00       100.00         100.00         100.00
mean         52.44       148.53          25.45          80.52
std          25.47        83.27          14.49          31.47
min          10.22         5.93           0.27           8.67
...
```

---

## Step 2. Prepare data - train/test split

Split data into two groups: one for training, one for testing. The model never sees the test data during training - this prevents cheating.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split

# sklearn is scikit-learn - the most popular ML library
# train_test_split splits your data into training and testing groups

# Recreate the data
np.random.seed(42)
n = 100
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
table_size_gb = np.random.uniform(0.1, 50, n)
query_time_ms = 0.5 * cpu + 0.1 * connections + 2.0 * table_size_gb + np.random.normal(0, 5, n)

df = pd.DataFrame({
    'cpu_percent': cpu,
    'connections': connections,
    'table_size_gb': table_size_gb,
    'query_time_ms': query_time_ms,
})

# --- Separate features (X) from label (y) ---
# X = the columns we use to predict (the inputs)
# y = the column we're predicting (the output)
#
# In SQL terms:
#   X = the WHERE clause columns
#   y = the column in SELECT that you want to predict

# .drop() removes a column. axis=1 means "column" (axis=0 would be "row")
X = df.drop('query_time_ms', axis=1)

# df['column_name'] selects one column
y = df['query_time_ms']

print(f"Features (X): {X.shape} - {list(X.columns)}")
print(f"Label (y): {y.shape} - query_time_ms")
print()

# --- Split into train and test ---
# test_size=0.2 means 20% for testing, 80% for training
# random_state=42 makes the split reproducible
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

print(f"Training set: {X_train.shape[0]} rows (80%)")
print(f"Test set:     {X_test.shape[0]} rows (20%)")
print()

# Why split?
print("Why split the data?")
print("  Training: the model learns patterns from this data")
print("  Testing:  we check if the model works on NEW data it's never seen")
print("  Without splitting: the model could memorize answers instead of learning")
print()
print("DBA analogy:")
print("  Training = tuning on your dev database")
print("  Testing  = verifying it works on production (different data)")
PYEOF
```

Expected output (yours will differ):
```
Features (X): (100, 3) - ['cpu_percent', 'connections', 'table_size_gb']
Label (y): (100,) - query_time_ms

Training set: 80 rows (80%)
Test set:     20 rows (20%)

Why split the data?
  Training: the model learns patterns from this data
  Testing:  we check if the model works on NEW data it's never seen
  Without splitting: the model could memorize answers instead of learning

DBA analogy:
  Training = tuning on your dev database
  Testing  = verifying it works on production (different data)
```

---

## Step 3. Train a linear regression model

Linear regression draws the best-fit line through your data. It learns a weight for each feature - exactly like the mini neural network in Module 05 Build 04.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression

# LinearRegression is the simplest ML model
# It learns: prediction = w1*cpu + w2*connections + w3*table_size + bias

# --- Setup data (same as before) ---
np.random.seed(42)
n = 100
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
table_size_gb = np.random.uniform(0.1, 50, n)
query_time_ms = 0.5 * cpu + 0.1 * connections + 2.0 * table_size_gb + np.random.normal(0, 5, n)

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'table_size_gb': table_size_gb, 'query_time_ms': query_time_ms,
})

X = df.drop('query_time_ms', axis=1)
y = df['query_time_ms']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# --- Train the model ---
# 1. Create the model object
model = LinearRegression()

# 2. Train it with .fit(features, labels)
#    This finds the best weights to minimize prediction error
#    It's doing gradient descent internally (from Module 05!)
model.fit(X_train, y_train)

print("Model trained!")
print()

# --- See what the model learned ---
# .coef_ contains the weights (one per feature)
# .intercept_ is the bias
print("What the model learned:")
for feature, weight in zip(X.columns, model.coef_):
    print(f"  {feature}: {weight:.4f}")
print(f"  bias (intercept): {model.intercept_:.4f}")
print()

# Compare to the actual formula we used to generate the data:
print("Actual formula: query_time = 0.5*cpu + 0.1*connections + 2.0*table_size + noise")
print("Model learned:  query_time = {:.2f}*cpu + {:.2f}*connections + {:.2f}*table_size + {:.2f}".format(
    model.coef_[0], model.coef_[1], model.coef_[2], model.intercept_
))
print()
print("The model discovered the hidden pattern from the data!")

# --- Make predictions ---
print()
print("Predictions vs actual (test set, first 5):")
predictions = model.predict(X_test)
for i in range(5):
    actual = y_test.iloc[i]
    predicted = predictions[i]
    error = abs(actual - predicted)
    print(f"  Actual: {actual:6.1f}ms  Predicted: {predicted:6.1f}ms  Error: {error:.1f}ms")
PYEOF
```

Expected output (yours will differ):
```
Model trained!

What the model learned:
  cpu_percent: 0.4982
  connections: 0.1013
  table_size_gb: 2.0036
  bias (intercept): -0.2987

Actual formula: query_time = 0.5*cpu + 0.1*connections + 2.0*table_size + noise
Model learned:  query_time = 0.50*cpu + 0.10*connections + 2.00*table_size + -0.30

The model discovered the hidden pattern from the data!

Predictions vs actual (test set, first 5):
  Actual:   76.4ms  Predicted:   78.2ms  Error: 1.8ms
  Actual:  106.2ms  Predicted:  104.5ms  Error: 1.7ms
  ...
```

The model found weights almost exactly matching the real formula (0.5, 0.1, 2.0). It discovered the pattern from data alone.

---

## Step 4. Evaluate the model

How good is the model? One number tells you: R-squared (R2). It ranges from 0 (terrible) to 1 (perfect).

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score

# --- Setup and train (same as before) ---
np.random.seed(42)
n = 100
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
table_size_gb = np.random.uniform(0.1, 50, n)
query_time_ms = 0.5 * cpu + 0.1 * connections + 2.0 * table_size_gb + np.random.normal(0, 5, n)

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'table_size_gb': table_size_gb, 'query_time_ms': query_time_ms,
})

X = df.drop('query_time_ms', axis=1)
y = df['query_time_ms']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

model = LinearRegression()
model.fit(X_train, y_train)
predictions = model.predict(X_test)

# --- Evaluation metrics ---

# R-squared (R2): how much of the variation in y does the model explain?
# 1.0 = perfect, 0.0 = useless, negative = worse than just guessing the mean
r2 = r2_score(y_test, predictions)

# Mean Squared Error (MSE): average squared difference between predicted and actual
# Lower is better. From Module 05 - same loss function!
mse = mean_squared_error(y_test, predictions)

# Root Mean Squared Error (RMSE): square root of MSE (same units as y)
# Easier to interpret: "on average, predictions are off by X ms"
rmse = np.sqrt(mse)

# Mean Absolute Error (MAE): average absolute difference
# Even easier to interpret, less sensitive to outliers
mae = mean_absolute_error(y_test, predictions)

print("Model Evaluation")
print("=" * 40)
print(f"R-squared (R2):              {r2:.4f}")
print(f"Mean Squared Error (MSE):    {mse:.2f}")
print(f"Root Mean Squared Error:     {rmse:.2f} ms")
print(f"Mean Absolute Error (MAE):   {mae:.2f} ms")
print()

print("What these mean:")
print(f"  R2 = {r2:.2f} means the model explains {r2*100:.0f}% of the variation in query time")
print(f"  RMSE = {rmse:.1f}ms means predictions are typically off by ~{rmse:.0f}ms")
print(f"  MAE = {mae:.1f}ms means the average error is ~{mae:.0f}ms")
print()

# Compare train vs test performance
train_r2 = model.score(X_train, y_train)  # .score() returns R2
test_r2 = model.score(X_test, y_test)
print(f"Train R2: {train_r2:.4f}")
print(f"Test R2:  {test_r2:.4f}")
gap = abs(train_r2 - test_r2)
if gap < 0.05:
    print(f"  Gap: {gap:.4f} - Good! Model generalizes well.")
elif gap < 0.15:
    print(f"  Gap: {gap:.4f} - OK but watch for overfitting.")
else:
    print(f"  Gap: {gap:.4f} - WARNING: possible overfitting!")
print()
print("If train R2 >> test R2, the model memorized training data (overfitting)")
print("If both are low, the model is too simple (underfitting)")
PYEOF
```

Expected output (yours will differ):
```
Model Evaluation
========================================
R-squared (R2):              0.9777
Mean Squared Error (MSE):    23.42
Root Mean Squared Error:     4.84 ms
Mean Absolute Error (MAE):   4.02 ms

What these mean:
  R2 = 0.98 means the model explains 98% of the variation in query time
  RMSE = 4.8ms means predictions are typically off by ~5ms
  MAE = 4.0ms means the average error is ~4ms

Train R2: 0.9756
Test R2:  0.9777
  Gap: 0.0021 - Good! Model generalizes well.

If train R2 >> test R2, the model memorized training data (overfitting)
If both are low, the model is too simple (underfitting)
```

---

## Step 5. The complete workflow in one script

Here's the full ML workflow - the pattern you'll use for every model.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression
from sklearn.metrics import r2_score, mean_absolute_error

print("""
THE ML WORKFLOW (same every time)
=================================

Step 1: Load data       ->  df = pd.read_csv('data.csv')
Step 2: Explore         ->  df.describe(), df.head()
Step 3: Prepare         ->  X = features, y = label, train_test_split()
Step 4: Train           ->  model.fit(X_train, y_train)
Step 5: Evaluate        ->  model.score(X_test, y_test)
Step 6: Predict         ->  model.predict(new_data)

That's it. Every ML project follows these 6 steps.
The only thing that changes is the model in Step 4.
""")

# --- Quick demo: predict query time for a brand new server ---
np.random.seed(42)
n = 100
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
table_size_gb = np.random.uniform(0.1, 50, n)
query_time_ms = 0.5 * cpu + 0.1 * connections + 2.0 * table_size_gb + np.random.normal(0, 5, n)

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'table_size_gb': table_size_gb, 'query_time_ms': query_time_ms,
})

X = df.drop('query_time_ms', axis=1)
y = df['query_time_ms']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

model = LinearRegression()
model.fit(X_train, y_train)

# Predict for a brand new server
# pd.DataFrame() with a list of dictionaries creates new rows
new_server = pd.DataFrame([{
    'cpu_percent': 75.0,
    'connections': 200,
    'table_size_gb': 30.0,
}])

predicted_time = model.predict(new_server)[0]
print(f"New server: CPU=75%, Connections=200, Table=30GB")
print(f"Predicted query time: {predicted_time:.1f}ms")
print()

# What we expect from the formula:
expected = 0.5 * 75 + 0.1 * 200 + 2.0 * 30
print(f"Expected (from formula): {expected:.1f}ms")
print(f"Model prediction:        {predicted_time:.1f}ms")
print(f"Close? {'Yes!' if abs(predicted_time - expected) < 10 else 'No'}")
PYEOF
```

Expected output (yours will differ):
```
THE ML WORKFLOW (same every time)
=================================

Step 1: Load data       ->  df = pd.read_csv('data.csv')
Step 2: Explore         ->  df.describe(), df.head()
Step 3: Prepare         ->  X = features, y = label, train_test_split()
Step 4: Train           ->  model.fit(X_train, y_train)
Step 5: Evaluate        ->  model.score(X_test, y_test)
Step 6: Predict         ->  model.predict(new_data)

That's it. Every ML project follows these 6 steps.
The only thing that changes is the model in Step 4.

New server: CPU=75%, Connections=200, Table=30GB
Predicted query time: 117.3ms

Expected (from formula): 117.5ms
Model prediction:        117.3ms
Close? Yes!
```

---

## What You Learned

| Concept | What It Is | Code |
|---------|-----------|------|
| DataFrame | A table (like a SQL result set) | `pd.DataFrame({...})` |
| Features (X) | Input columns used for prediction | `X = df.drop('label', axis=1)` |
| Label (y) | The column you're predicting | `y = df['label']` |
| Train/test split | 80/20 split to prevent cheating | `train_test_split(X, y, test_size=0.2)` |
| Linear Regression | Draws a best-fit line | `model = LinearRegression()` |
| .fit() | Train the model | `model.fit(X_train, y_train)` |
| .predict() | Make predictions | `model.predict(new_data)` |
| .score() | R2 evaluation (0=bad, 1=perfect) | `model.score(X_test, y_test)` |
| R2 | % of variation explained by the model | 0.98 = model explains 98% |
| RMSE | Average prediction error (in original units) | 4.8ms = off by ~5ms typically |
