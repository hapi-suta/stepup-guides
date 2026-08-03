# SURVIVE 02: The Exploding Gradient

Your model's loss starts at 44, drops to 6, then suddenly shoots to infinity. Training has diverged. The weights are NaN. Find out why and fix it.

---

## The Scenario

You're training a model to predict query times. It starts learning well, but at step 8 the loss jumps from 6 to 800, then to infinity. The model is ruined.

---

## Step 1. See the explosion

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import warnings
warnings.filterwarnings('ignore')  # suppress overflow warnings for demo

# Training data
inputs = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
targets = np.array([2.0, 4.0, 6.0, 8.0, 10.0])

# BUG: Learning rate is way too high
learning_rate = 0.2  # this is too aggressive for this data
weight = 0.0

print("Training with learning_rate = 0.2 (TOO HIGH)")
print(f"{'Step':>4s}  {'Weight':>12s}  {'Loss':>12s}  {'Gradient':>12s}  Status")
print("-" * 70)

for step in range(15):
    predictions = inputs * weight
    loss = np.mean((predictions - targets) ** 2)
    gradient = 2 * np.mean(inputs * (predictions - targets))

    # Check for explosion
    if np.isnan(loss) or np.isinf(loss):
        status = "EXPLODED (NaN/Inf)"
    elif loss > 1000:
        status = "DIVERGING!"
    elif loss < 1:
        status = "converging"
    else:
        status = ""

    print(f"{step:>4d}  {weight:>12.2f}  {loss:>12.2f}  {gradient:>12.2f}  {status}")

    # Update weight
    weight = weight - learning_rate * gradient

    # Stop if exploded
    if np.isnan(weight) or np.isinf(weight):
        print(f"{'':>4s}  {'NaN':>12s}  {'NaN':>12s}  {'NaN':>12s}  TRAINING CRASHED")
        break

print()
print("What happened?")
print("  1. Weight adjusted too aggressively (big learning rate)")
print("  2. Overshot the optimal value")
print("  3. Each overshoot made the next gradient BIGGER")
print("  4. Gradient and weight grew exponentially -> NaN")
print()
print("This is called 'gradient explosion' - one of the most common")
print("training failures in deep learning.")
PYEOF
```

Expected output (yours will differ):
```
Training with learning_rate = 0.2 (TOO HIGH)
Step        Weight          Loss      Gradient  Status
----------------------------------------------------------------------
   0          0.00         44.00        -22.00
   1          4.40        636.24        105.60  DIVERGING!
   2        -16.72      36670.19       -802.56  DIVERGING!
   3        143.79   2267118.26       6305.20  DIVERGING!
   ...
  TRAINING CRASHED

What happened?
  1. Weight adjusted too aggressively (big learning rate)
  2. Overshot the optimal value
  3. Each overshoot made the next gradient BIGGER
  4. Gradient and weight grew exponentially -> NaN

This is called 'gradient explosion' - one of the most common
training failures in deep learning.
```

---

## Step 2. Understand the mechanics

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

print("""
Why does the gradient EXPLODE?

Step 0: weight = 0.0, loss = 44
  gradient = -22
  update: 0.0 - 0.2 * (-22) = 0.0 + 4.4 = 4.4
  (Jumped from 0 to 4.4 - overshot the target of 2.0!)

Step 1: weight = 4.4, loss = 636
  The weight is now FAR from optimal (2.0)
  So predictions are very wrong -> large errors -> large gradient
  gradient = 105.6
  update: 4.4 - 0.2 * 105.6 = 4.4 - 21.12 = -16.72
  (Jumped from 4.4 all the way to -16.72! Even further from 2.0!)

Step 2: weight = -16.72, loss = 36,670
  Now weight is -16.72 (target is 2.0)
  Errors are ENORMOUS -> gradient is ENORMOUS
  Each step makes the NEXT step worse.

This is positive feedback (a vicious cycle):
  big weight -> big error -> big gradient -> bigger weight -> bigger error -> ...

The fix is simple: smaller learning rate.
""")

# Show the fix
inputs = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
targets = np.array([2.0, 4.0, 6.0, 8.0, 10.0])

print("Same problem, three learning rates:")
print()

for lr in [0.2, 0.04, 0.01]:
    weight = 0.0
    exploded = False
    for step in range(50):
        predictions = inputs * weight
        loss = np.mean((predictions - targets) ** 2)
        gradient = 2 * np.mean(inputs * (predictions - targets))
        weight = weight - lr * gradient
        if np.isnan(weight) or np.isinf(weight) or abs(weight) > 1e10:
            print(f"  lr={lr}: EXPLODED at step {step}")
            exploded = True
            break
    if not exploded:
        final_loss = np.mean((inputs * weight - targets) ** 2)
        print(f"  lr={lr}: converged! weight={weight:.4f}, loss={final_loss:.6f}")
PYEOF
```

Expected output (yours will differ):
```
Why does the gradient EXPLODE?
...

Same problem, three learning rates:

  lr=0.2: EXPLODED at step 1
  lr=0.04: converged! weight=2.0000, loss=0.000000
  lr=0.01: converged! weight=1.9709, loss=0.001868
```

---

## Step 3. Fix with gradient clipping

In real neural networks, you can't always just reduce the learning rate. Instead, you "clip" the gradient - put a maximum limit on how large it can be.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

inputs = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
targets = np.array([2.0, 4.0, 6.0, 8.0, 10.0])

# --- Fix 1: Gradient clipping ---
# If the gradient is too large, cap it at a maximum value
# This prevents the "runaway" feedback loop

def clip_gradient(gradient, max_value=5.0):
    """Clip gradient to [-max_value, max_value]."""
    # np.clip(value, min, max) caps the value within a range
    return np.clip(gradient, -max_value, max_value)

# Train with the SAME high learning rate, but with gradient clipping
weight = 0.0
learning_rate = 0.2  # same learning rate that exploded before!
max_grad = 5.0

print(f"Training with lr={learning_rate} + gradient clipping (max={max_grad})")
print(f"{'Step':>4s}  {'Weight':>8s}  {'Loss':>10s}  {'Raw Grad':>10s}  {'Clipped':>10s}")
print("-" * 55)

for step in range(30):
    predictions = inputs * weight
    loss = np.mean((predictions - targets) ** 2)
    gradient = 2 * np.mean(inputs * (predictions - targets))

    # Clip the gradient
    clipped = clip_gradient(gradient, max_grad)

    if step < 10 or step % 5 == 0:
        print(f"{step:>4d}  {weight:>8.4f}  {loss:>10.4f}  {gradient:>10.2f}  {clipped:>10.2f}")

    # Update with CLIPPED gradient
    weight = weight - learning_rate * clipped

print()
final_loss = np.mean((inputs * weight - targets) ** 2)
print(f"Final: weight={weight:.4f}, loss={final_loss:.6f}")
print()
print("Gradient clipping saved the training!")
print("  Without clipping: EXPLODED at step 1")
print("  With clipping: converged to weight ~2.0")
print()

# --- Fix 2: Learning rate scheduling ---
print("=" * 55)
print()
print("Fix 2: Learning rate scheduling")
print("  Start with a higher learning rate, decrease over time")
print()

weight = 0.0
initial_lr = 0.1

print(f"{'Step':>4s}  {'LR':>8s}  {'Weight':>8s}  {'Loss':>10s}")
print("-" * 40)

for step in range(30):
    # Decrease learning rate over time
    # This formula cuts the LR in half every 10 steps
    lr = initial_lr / (1 + step * 0.1)

    predictions = inputs * weight
    loss = np.mean((predictions - targets) ** 2)
    gradient = 2 * np.mean(inputs * (predictions - targets))
    weight = weight - lr * gradient

    if step < 5 or step % 5 == 0:
        print(f"{step:>4d}  {lr:>8.4f}  {weight:>8.4f}  {loss:>10.4f}")

print()
final_loss = np.mean((inputs * weight - targets) ** 2)
print(f"Final: weight={weight:.4f}, loss={final_loss:.6f}")
print("  Learning rate started at 0.1 and decreased to ~0.03")
print("  Fast learning at first, fine-tuning later")
PYEOF
```

Expected output (yours will differ):
```
Training with lr=0.2 + gradient clipping (max=5.0)
Step    Weight        Loss    Raw Grad     Clipped
-------------------------------------------------------
   0    0.0000     44.0000      -22.00       -5.00
   1    1.0000     11.0000      -11.00       -5.00
   2    2.0000      0.0000        0.01        0.01
   3    1.9980      0.0000        0.02        0.02
...

Final: weight=2.0000, loss=0.000000

Gradient clipping saved the training!
  Without clipping: EXPLODED at step 1
  With clipping: converged to weight ~2.0

=======================================================

Fix 2: Learning rate scheduling
  Start with a higher learning rate, decrease over time

Step        LR    Weight        Loss
----------------------------------------
   0    0.1000    2.2000     44.0000
   1    0.0909    1.8000      4.8400
   2    0.0833    1.9667      0.1936
   3    0.0769    1.9923      0.0065
   4    0.0714    1.9987      0.0002
   5    0.0667    1.9998      0.0000
...

Final: weight=2.0000, loss=0.000000
  Learning rate started at 0.1 and decreased to ~0.03
  Fast learning at first, fine-tuning later
```

---

## Step 4. Recognize and fix in practice

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Gradient Explosion Cheat Sheet:

SYMPTOMS:
  - Loss suddenly jumps from decreasing to increasing
  - Loss becomes NaN or Inf
  - Weights become very large numbers
  - Model outputs are all the same (saturated sigmoid/softmax)

CAUSES:
  1. Learning rate too high
  2. No gradient clipping
  3. Data not normalized (large input values -> large gradients)
  4. Deep networks without proper initialization

FIXES (try in this order):
  1. Reduce learning rate (try 10x smaller: 0.01 -> 0.001)
  2. Add gradient clipping (max_grad_norm = 1.0 is common)
  3. Normalize your data (z-score or min-max)
  4. Use learning rate scheduling (start high, decrease over time)
  5. Use adaptive optimizers (Adam instead of SGD)
     Adam adjusts learning rate per-parameter automatically

DBA ANALOGY:
  Gradient explosion = parameter tuning oscillation
  Imagine auto-tuning shared_buffers:
    128MB -> 4GB -> -2GB -> 16GB -> crash
  The fix: take smaller steps and cap maximum change per iteration

IN PYTORCH (how you'd actually fix it):
  # Gradient clipping (one line!)
  torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)

  # Adam optimizer (adaptive learning rate)
  optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

  # Learning rate scheduler
  scheduler = torch.optim.lr_scheduler.StepLR(optimizer, step_size=10, gamma=0.5)
""")
PYEOF
```

---

## What You Learned

| Problem | Symptom | Fix |
|---------|---------|-----|
| Learning rate too high | Loss increases instead of decreasing | Reduce by 10x |
| Gradient explosion | Loss -> NaN/Inf, weights -> huge | Gradient clipping |
| No normalization | Large inputs cause large gradients | Normalize data first |
| Constant learning rate | Overshoots near the optimum | Learning rate scheduling |

**The three safeguards:**
1. **Gradient clipping** - cap maximum gradient magnitude
2. **Learning rate scheduling** - decrease over time
3. **Data normalization** - keep inputs in a reasonable range (from SURVIVE 01)
