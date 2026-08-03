# Build 02: Regression Metrics and Model Calibration

When your model predicts numbers (query time, CPU usage) or probabilities (incident likelihood), you need different metrics. This guide covers regression evaluation and calibration - does the model's confidence match reality?

---

## Step 1. Regression metrics

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score

np.random.seed(42)

# Simulate: model predicts query execution time (in milliseconds)
n = 100
y_true = np.random.uniform(5, 500, n)  # actual query times: 5ms to 500ms
# Simulated prediction with some error
noise = np.random.normal(0, 30, n)  # ~30ms average error
y_pred = y_true + noise
y_pred = np.clip(y_pred, 0, None)  # no negative times
# np.clip(values, min, max): None means no upper limit

# Metric 1: RMSE (Root Mean Squared Error)
rmse = np.sqrt(mean_squared_error(y_true, y_pred))
# sqrt of average of (prediction - actual)^2
# In the SAME UNITS as the target (milliseconds)
# Penalizes large errors more than small ones

# Metric 2: MAE (Mean Absolute Error)
mae = mean_absolute_error(y_true, y_pred)
# Average of |prediction - actual|
# In the SAME UNITS as the target (milliseconds)
# Less sensitive to outliers than RMSE

# Metric 3: R2 (R-squared / coefficient of determination)
r2 = r2_score(y_true, y_pred)
# How much variance does the model explain?
# 1.0 = perfect, 0.0 = no better than predicting the mean, negative = worse than mean

# Metric 4: MAPE (Mean Absolute Percentage Error)
mape = np.mean(np.abs((y_true - y_pred) / y_true)) * 100
# Error as a percentage of actual value
# Useful when targets have very different scales

print("Regression Metrics for Query Time Prediction:")
print("=" * 50)
print(f"  RMSE:  {rmse:.1f} ms   (average error magnitude)")
print(f"  MAE:   {mae:.1f} ms   (average absolute error)")
print(f"  R2:    {r2:.3f}      (variance explained, 1.0 = perfect)")
print(f"  MAPE:  {mape:.1f}%      (average % error)")
print()

# Show some predictions
print(f"{'Actual (ms)':>12s}  {'Predicted':>10s}  {'Error':>8s}")
print("-" * 35)
for i in range(8):
    error = y_pred[i] - y_true[i]
    print(f"{y_true[i]:>12.1f}  {y_pred[i]:>10.1f}  {error:>+8.1f}")

print()
print("When to use which metric:")
print("  RMSE: when large errors are much worse than small errors")
print("  MAE:  when all errors matter equally")
print("  R2:   when comparing models (higher = better)")
print("  MAPE: when you need error as a percentage")
PYEOF
```

Expected output (yours will differ):

```
Regression Metrics for Query Time Prediction:
==================================================
  RMSE:  31.2 ms   (average error magnitude)
  MAE:   24.8 ms   (average absolute error)
  R2:    0.952      (variance explained, 1.0 = perfect)
  MAPE:  15.3%      (average % error)
```

---

## Step 2. Model calibration

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

np.random.seed(42)

print("""
Model Calibration: Does the model's confidence match reality?

If the model says "90% chance of incident", does an incident
actually happen 90% of the time?

A well-calibrated model:
  - When it says 90% -> incidents happen ~90% of the time
  - When it says 50% -> incidents happen ~50% of the time
  - When it says 10% -> incidents happen ~10% of the time

An overconfident model:
  - When it says 90% -> incidents happen only 60% of the time
  - The model is LYING about its certainty

Why it matters for DBAs:
  If your model says "95% chance this server will crash"
  and you trust that number, you'll take expensive action.
  If the model is overconfident, you'll waste resources.
""")

# Simulate: 1000 predictions with probabilities
n = 1000
y_true = np.zeros(n, dtype=int)
y_true[:200] = 1  # 20% base incident rate
np.random.shuffle(y_true)

# Well-calibrated model
probs_good = np.random.beta(2, 8, n)  # mostly low probabilities
probs_good[y_true == 1] = np.random.beta(5, 2, 200)  # incidents get high probs
probs_good = np.clip(probs_good, 0.01, 0.99)

# Overconfident model (pushes everything toward 0 or 1)
probs_overconfident = probs_good ** 0.3  # compresses toward 1
probs_overconfident[probs_good < 0.3] = probs_good[probs_good < 0.3] ** 3  # pushes low values lower

def calibration_check(y_true, probs, name, bins=5):
    """Check if predicted probabilities match actual frequencies."""
    print(f"\n{name}:")
    print(f"  {'Prob Range':>15s}  {'Predicted':>10s}  {'Actual':>8s}  {'Count':>6s}  {'Status':>10s}")
    print(f"  {'-'*55}")

    bin_edges = np.linspace(0, 1, bins + 1)
    # np.linspace(0, 1, 6) = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

    for i in range(bins):
        mask = (probs >= bin_edges[i]) & (probs < bin_edges[i+1])
        # mask is a boolean array: True where probability falls in this bin
        if mask.sum() == 0:
            continue
        predicted_avg = probs[mask].mean()
        actual_avg = y_true[mask].mean()
        count = mask.sum()
        gap = abs(predicted_avg - actual_avg)
        status = "OK" if gap < 0.1 else "OFF" if gap < 0.2 else "BAD"
        print(f"  {bin_edges[i]:.1f} - {bin_edges[i+1]:.1f}       "
              f"{predicted_avg:>7.1%}    {actual_avg:>6.1%}  {count:>6d}  {status:>10s}")

calibration_check(y_true, probs_good, "Well-Calibrated Model")
calibration_check(y_true, probs_overconfident, "Overconfident Model")

print()
print("Well-calibrated: predicted % closely matches actual %")
print("Overconfident: says 80% but actual is only 50%")
print("Always check calibration before trusting model confidence!")
PYEOF
```

Expected output (yours will differ):

```
Well-Calibrated Model:
  Prob Range     Predicted    Actual   Count      Status
  -------------------------------------------------------
  0.0 - 0.2          12.5%    10.2%      450          OK
  0.2 - 0.4          29.8%    25.1%      200          OK
  0.4 - 0.6          49.2%    45.0%      150          OK
  0.6 - 0.8          68.5%    70.2%      120          OK
  0.8 - 1.0          88.1%    85.0%       80          OK

Overconfident Model:
  ...
  0.8 - 1.0          92.3%    55.0%      350         BAD
```

---

## Step 3. Prediction intervals

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

np.random.seed(42)

print("""
Prediction Intervals: Not just the prediction, but the range.

Instead of: "Query will take 150ms"
Better:     "Query will take 150ms (90% interval: 80ms - 220ms)"

DBA analogy: Like reporting p99 latency, not just average.
  Average response: 50ms (but p99 is 500ms!)
  The range tells you more than a single number.
""")

# Simulate multiple predictions for the same inputs (ensemble or MC dropout)
n_examples = 10
n_samples = 100  # run prediction 100 times with slight variation

# Simulate: model predictions with uncertainty
base_predictions = np.random.uniform(50, 300, n_examples)
# For each example, simulate 100 predictions with noise
all_predictions = np.array([
    base_predictions + np.random.normal(0, base_predictions * 0.15, n_examples)
    # noise proportional to prediction (larger predictions have more uncertainty)
    for _ in range(n_samples)
])
# all_predictions shape: [100, 10] - 100 samples for 10 examples

# Calculate prediction intervals
mean_pred = all_predictions.mean(axis=0)       # average across 100 samples
lower_90 = np.percentile(all_predictions, 5, axis=0)   # 5th percentile
upper_90 = np.percentile(all_predictions, 95, axis=0)  # 95th percentile
# 5th to 95th percentile = 90% prediction interval

print(f"Query Time Predictions with 90% Confidence Intervals:")
print(f"{'Query':>6s}  {'Predicted':>10s}  {'90% Lower':>10s}  {'90% Upper':>10s}  {'Range':>8s}")
print("-" * 50)

for i in range(n_examples):
    range_width = upper_90[i] - lower_90[i]
    print(f"{i+1:>6d}  {mean_pred[i]:>9.0f}ms  {lower_90[i]:>9.0f}ms  {upper_90[i]:>9.0f}ms  {range_width:>6.0f}ms")

print()
print("Wide range = model is UNCERTAIN (be careful)")
print("Narrow range = model is CONFIDENT (more trustworthy)")
print()
print("In production:")
print("  - Use the mean prediction for display")
print("  - Use the upper bound for capacity planning")
print("  - Flag predictions with wide ranges for human review")
PYEOF
```

---

## What You Learned

| Concept | What It Tells You | When to Use |
|---------|------------------|-------------|
| RMSE | Average error size (penalizes large errors) | When big mistakes are much worse |
| MAE | Average error size (all errors equal) | When all errors matter the same |
| R2 | % of variance explained | Comparing regression models |
| Calibration | Does confidence match reality? | Before trusting model probabilities |
| Prediction intervals | Range of possible outcomes | When uncertainty matters (capacity planning) |
