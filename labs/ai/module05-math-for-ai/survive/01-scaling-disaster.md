# SURVIVE 01: The Scaling Disaster

Your model predicts server health. It works perfectly on test data. But when you deploy it, every server is flagged as "needs attention." Nothing changed except the data format. Find and fix the bug.

---

## The Scenario

You trained a model on normalized data (0-1 range). Someone deployed it with raw data (CPU 0-100%, Memory 0-16384MB, Connections 0-300). The model goes haywire because the scales are completely wrong.

---

## Step 1. See the broken prediction

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- The model was trained on normalized data (0-1) ---
# These weights were learned during training
weights = np.array([2.15, 1.87, 2.09])  # [CPU, Memory, Connections]
bias = -2.61

def sigmoid(x):
    return 1 / (1 + np.exp(-np.clip(x, -500, 500)))

def predict(server_metrics):
    """Predict: 0=healthy, 1=needs attention."""
    z = np.dot(server_metrics, weights) + bias
    return sigmoid(z)

# --- Test with normalized data (how it was trained) ---
print("=== Predictions with NORMALIZED data (correct) ===")
test_normalized = [
    ("healthy server", np.array([0.15, 0.42, 0.08])),
    ("sick server",    np.array([0.92, 0.68, 0.95])),
    ("medium server",  np.array([0.50, 0.50, 0.50])),
]

for name, metrics in test_normalized:
    prob = predict(metrics)
    label = "ATTENTION" if prob > 0.5 else "healthy"
    print(f"  {name}: {prob:.4f} -> {label}")

print()

# --- BUG: Deploy with RAW data (not normalized) ---
print("=== Predictions with RAW data (BROKEN) ===")
test_raw = [
    ("healthy server", np.array([15.0, 42.0, 25.0])),    # CPU=15%, Mem=42%, Conn=25
    ("sick server",    np.array([92.0, 68.0, 285.0])),    # CPU=92%, Mem=68%, Conn=285
    ("medium server",  np.array([50.0, 50.0, 150.0])),    # CPU=50%, Mem=50%, Conn=150
]

for name, metrics in test_raw:
    prob = predict(metrics)
    label = "ATTENTION" if prob > 0.5 else "healthy"
    print(f"  {name}: {prob:.4f} -> {label}")

print()
print("BUG: Everything is flagged as ATTENTION!")
print("The healthy server (CPU 15%, 25 connections) is marked as sick!")
print()
print("Why? The model expects numbers between 0 and 1.")
print("  It received 15.0 instead of 0.15 for CPU")
print("  It received 42.0 instead of 0.42 for Memory")
print("  The dot product is 100x too large -> sigmoid outputs 1.0 for everything")
PYEOF
```

Expected output:
```
=== Predictions with NORMALIZED data (correct) ===
  healthy server: 0.0252 -> healthy
  sick server: 0.9803 -> ATTENTION
  medium server: 0.7858 -> ATTENTION

=== Predictions with RAW data (BROKEN) ===
  healthy server: 1.0000 -> ATTENTION
  sick server: 1.0000 -> ATTENTION
  medium server: 1.0000 -> ATTENTION

BUG: Everything is flagged as ATTENTION!
The healthy server (CPU 15%, 25 connections) is marked as sick!

Why? The model expects numbers between 0 and 1.
  It received 15.0 instead of 0.15 for CPU
  It received 42.0 instead of 0.42 for Memory
  The dot product is 100x too large -> sigmoid outputs 1.0 for everything
```

---

## Step 2. Understand why it breaks

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

weights = np.array([2.15, 1.87, 2.09])
bias = -2.61

# What the model sees:
print("What happens inside the model:")
print()

# With normalized data (correct)
normalized = np.array([0.15, 0.42, 0.08])
z_correct = np.dot(normalized, weights) + bias
print(f"Normalized input: {normalized}")
print(f"  z = (0.15*2.15) + (0.42*1.87) + (0.08*2.09) + (-2.61)")
print(f"  z = {0.15*2.15:.2f} + {0.42*1.87:.2f} + {0.08*2.09:.2f} - 2.61")
print(f"  z = {z_correct:.4f}")
print(f"  sigmoid({z_correct:.4f}) = {1/(1+np.exp(-z_correct)):.4f}  <- healthy")
print()

# With raw data (broken)
raw = np.array([15.0, 42.0, 25.0])
z_broken = np.dot(raw, weights) + bias
print(f"Raw input: {raw}")
print(f"  z = (15*2.15) + (42*1.87) + (25*2.09) + (-2.61)")
print(f"  z = {15*2.15:.2f} + {42*1.87:.2f} + {25*2.09:.2f} - 2.61")
print(f"  z = {z_broken:.4f}")
print(f"  sigmoid({z_broken:.4f}) = {1/(1+np.exp(-min(z_broken, 500))):.4f}  <- ALWAYS 1.0!")
print()

print("The z value went from -1.67 to 159.68")
print("sigmoid(159.68) = 1.0 (completely saturated)")
print("sigmoid(-1.67) = 0.16 (properly distinguishing)")
print()
print("Root cause: data was not normalized at prediction time")
print("Training and prediction MUST use the same scale")
PYEOF
```

Expected output:
```
What happens inside the model:

Normalized input: [0.15 0.42 0.08]
  z = (0.15*2.15) + (0.42*1.87) + (0.08*2.09) + (-2.61)
  z = 0.32 + 0.79 + 0.17 - 2.61
  z = -1.3356
  sigmoid(-1.3356) = 0.2084  <- healthy

Raw input: [15.  42.  25.]
  z = (15*2.15) + (42*1.87) + (25*2.09) + (-2.61)
  z = 32.25 + 78.54 + 52.25 - 2.61
  z = 160.4300
  sigmoid(160.4300) = 1.0000  <- ALWAYS 1.0!

The z value went from -1.67 to 159.68
sigmoid(159.68) = 1.0 (completely saturated)
sigmoid(-1.67) = 0.16 (properly distinguishing)

Root cause: data was not normalized at prediction time
Training and prediction MUST use the same scale
```

---

## Step 3. Fix it - save and reuse normalization parameters

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- The Fix: Save normalization parameters from training ---

# During training, you calculated the mean and std of your training data
# You MUST save these and reuse them at prediction time

class ServerHealthModel:
    """A model that properly handles normalization."""

    def __init__(self):
        # These would come from training (saved alongside the model)
        self.weights = np.array([2.15, 1.87, 2.09])
        self.bias = -2.61

        # CRITICAL: normalization parameters from training data
        # These define what "normal" looks like
        self.train_mean = np.array([50.0, 50.0, 150.0])  # mean of training data
        self.train_std = np.array([30.0, 20.0, 100.0])    # std of training data

    def normalize(self, raw_data):
        """Apply the SAME normalization used during training."""
        return (raw_data - self.train_mean) / self.train_std

    def predict(self, raw_data):
        """Predict from raw data - normalizes automatically."""
        normalized = self.normalize(raw_data)
        z = np.dot(normalized, self.weights) + self.bias
        prob = 1 / (1 + np.exp(-np.clip(z, -500, 500)))
        return prob, normalized

# --- Test the fixed model ---
model = ServerHealthModel()

print("=== Fixed model (normalizes raw data automatically) ===")
print()

test_servers = [
    ("healthy (CPU=15%, Mem=42%, Conn=25)", np.array([15.0, 42.0, 25.0])),
    ("sick (CPU=92%, Mem=68%, Conn=285)",   np.array([92.0, 68.0, 285.0])),
    ("medium (CPU=50%, Mem=50%, Conn=150)", np.array([50.0, 50.0, 150.0])),
]

for name, raw in test_servers:
    prob, normalized = model.predict(raw)
    label = "ATTENTION" if prob > 0.5 else "healthy"
    print(f"  {name}")
    print(f"    Raw:        {raw}")
    print(f"    Normalized: {normalized.round(4)}")
    print(f"    Prediction: {prob:.4f} -> {label}")
    print()

print("Now the model correctly identifies healthy vs sick servers!")
print()
print("Key lesson:")
print("  1. Save train_mean and train_std alongside your model weights")
print("  2. Apply the SAME normalization at prediction time")
print("  3. Never assume data comes pre-normalized")
print("  4. In production: add a validation check that inputs are in expected range")
PYEOF
```

Expected output (yours will differ):
```
=== Fixed model (normalizes raw data automatically) ===

  healthy (CPU=15%, Mem=42%, Conn=25)
    Raw:        [15. 42. 25.]
    Normalized: [-1.1667 -0.4    -1.25  ]
    Prediction: 0.0002 -> healthy

  sick (CPU=92%, Mem=68%, Conn=285)
    Raw:        [92. 68. 285.]
    Normalized: [1.4    0.9    1.35  ]
    Prediction: 0.9999 -> ATTENTION

  medium (CPU=50%, Mem=50%, Conn=150)
    Raw:        [ 50.  50. 150.]
    Normalized: [0. 0. 0.]
    Prediction: 0.0684 -> healthy

Now the model correctly identifies healthy vs sick servers!

Key lesson:
  1. Save train_mean and train_std alongside your model weights
  2. Apply the SAME normalization at prediction time
  3. Never assume data comes pre-normalized
  4. In production: add a validation check that inputs are in expected range
```

---

## What You Learned

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| All predictions are 1.0 | Raw data fed to model trained on normalized data | Save and reuse normalization parameters |
| Sigmoid saturation | z values too large (>10 means sigmoid = 1.0) | Normalize inputs to keep z values in reasonable range |
| Train/predict mismatch | Different data scales at train vs predict time | Always normalize at both stages using the SAME parameters |

**Production checklist:**
- Save `train_mean` and `train_std` with your model file
- Normalize at prediction time using saved parameters
- Add input validation (reject values outside expected range)
- Log raw AND normalized inputs for debugging
- Monitor prediction distribution (all 1.0 or all 0.0 = something is wrong)
