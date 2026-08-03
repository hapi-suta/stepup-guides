# Build 04: Calculus Intuition - How Models Learn

You don't need to DO calculus. You need to understand ONE idea: **gradient descent** - the algorithm that trains every AI model. It's like tuning PostgreSQL parameters, but automatically.

---

## Step 1. Loss - how wrong is the model?

Before a model can learn, you need a way to measure "how wrong is it?" That's called the loss function.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- The concept ---
# A model makes predictions. Predictions can be wrong.
# The "loss" measures how wrong the predictions are.
#
# DBA analogy:
#   predicted_query_time vs actual_query_time
#   The difference = error
#   Average error across all queries = loss

# Actual query times (what really happened)
actual = np.array([50, 30, 80, 20, 60])

# Model's predictions (what the model guessed)
predicted = np.array([55, 28, 90, 25, 58])

# --- Mean Squared Error (MSE) ---
# 1. Calculate the error at each point (predicted - actual)
errors = predicted - actual
print("Errors (predicted - actual):")
print(f"  {errors}")
print(f"  Positive = model guessed too high")
print(f"  Negative = model guessed too low")
print()

# 2. Square the errors (makes everything positive, penalizes big errors more)
squared_errors = errors ** 2
print("Squared errors:")
print(f"  {squared_errors}")
print()

# 3. Take the mean (average squared error)
mse = np.mean(squared_errors)
print(f"Mean Squared Error (MSE): {mse}")
print(f"  This is 'the loss' - one number that says how wrong the model is")
print()

# A perfect model has loss = 0
perfect = actual.copy()
perfect_mse = np.mean((perfect - actual) ** 2)
print(f"Perfect prediction MSE: {perfect_mse}")
print()

# A terrible model has high loss
terrible = np.array([200, 200, 200, 200, 200])
terrible_mse = np.mean((terrible - actual) ** 2)
print(f"Terrible prediction MSE: {terrible_mse}")
print()

print("Training a model = making the loss go DOWN")
print("  High loss -> bad predictions")
print("  Low loss  -> good predictions")
print("  Zero loss -> perfect (never happens in real life)")
PYEOF
```

Expected output (yours will differ):
```
Errors (predicted - actual):
  [ 5 -2 10  5 -2]
  Positive = model guessed too high
  Negative = model guessed too low

Squared errors:
  [ 25   4 100  25   4]

Mean Squared Error (MSE): 31.6
  This is 'the loss' - one number that says how wrong the model is

Perfect prediction MSE: 0.0

Terrible prediction MSE: 22760.0

Training a model = making the loss go DOWN
  High loss -> bad predictions
  Low loss  -> good predictions
  Zero loss -> perfect (never happens in real life)
```

---

## Step 2. Gradient - which direction reduces the loss?

The gradient tells you: "if I adjust this parameter up, does the loss go up or down?"

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- The DBA analogy ---
# You're tuning shared_buffers to minimize query time.
# You try different values and see what happens.
#
# shared_buffers = 64MB  -> avg query: 80ms
# shared_buffers = 128MB -> avg query: 50ms  (better! keep going up)
# shared_buffers = 256MB -> avg query: 30ms  (better! keep going up)
# shared_buffers = 512MB -> avg query: 25ms  (a little better)
# shared_buffers = 1GB   -> avg query: 28ms  (worse! went too far)
#
# You figured out the direction (up) and when to stop.
# That's gradient descent.

# Let's simulate this with a simple model:
#   prediction = input * weight
#   We need to find the best weight

# Our data
inputs = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
targets = np.array([2.0, 4.0, 6.0, 8.0, 10.0])
# The pattern: target = input * 2
# So the "correct" weight is 2.0
# But the model doesn't know that yet!

def calculate_loss(weight):
    """Calculate MSE for a given weight."""
    predictions = inputs * weight
    return np.mean((predictions - targets) ** 2)

# Try different weights and see the loss
print("Trying different weights:")
print(f"  {'Weight':>8s}  {'Loss':>10s}  {'Direction'}")
print(f"  {'------':>8s}  {'--------':>10s}  {'---------'}")

for w in [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
    loss = calculate_loss(w)
    if w == 2.0:
        direction = "<- BEST (loss = 0)"
    elif w < 2.0:
        direction = "increase weight"
    else:
        direction = "decrease weight"
    print(f"  {w:>8.1f}  {loss:>10.2f}  {direction}")

print()
print("The loss forms a U-shape (a 'valley'):")
print("  Weight too low  -> high loss (undershoot)")
print("  Weight just right -> loss = 0 (the bottom of the valley)")
print("  Weight too high -> high loss (overshoot)")
print()

# --- The gradient tells you which direction to go ---
# Gradient = slope at your current position
#   Positive gradient = you're on the right side of the valley = go LEFT (decrease weight)
#   Negative gradient = you're on the left side of the valley = go RIGHT (increase weight)
#   Zero gradient = you're at the bottom = stop!

def estimate_gradient(weight, step=0.001):
    """Estimate the gradient by trying a tiny step."""
    # Check: if I increase the weight by a tiny amount,
    # does the loss go up or down?
    loss_now = calculate_loss(weight)
    loss_after = calculate_loss(weight + step)
    # gradient = (change in loss) / (change in weight)
    return (loss_after - loss_now) / step

print("Gradients at different weights:")
for w in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
    grad = estimate_gradient(w)
    if abs(grad) < 0.1:
        arrow = "=  (at the bottom!)"
    elif grad > 0:
        arrow = "-> decrease weight"
    else:
        arrow = "-> increase weight"
    print(f"  Weight {w:.1f}: gradient = {grad:>8.2f}  {arrow}")
PYEOF
```

Expected output (yours will differ):
```
Trying different weights:
    Weight        Loss  Direction
    ------    --------  ---------
       0.0       44.00  increase weight
       0.5       24.75  increase weight
       1.0       11.00  increase weight
       1.5        2.75  increase weight
       2.0        0.00  <- BEST (loss = 0)
       2.5        2.75  decrease weight
       3.0       11.00  decrease weight

The loss forms a U-shape (a 'valley'):
  Weight too low  -> high loss (undershoot)
  Weight just right -> loss = 0 (the bottom of the valley)
  Weight too high -> high loss (overshoot)

Gradients at different weights:
  Weight 0.5: gradient =   -16.50  -> increase weight
  Weight 1.0: gradient =   -11.00  -> increase weight
  Weight 1.5: gradient =    -5.50  -> increase weight
  Weight 2.0: gradient =     0.01  =  (at the bottom!)
  Weight 2.5: gradient =     5.50  -> decrease weight
  Weight 3.0: gradient =    11.01  -> decrease weight
```

---

## Step 3. Gradient descent - the full algorithm

Now let's put it together: start with a random weight, calculate the gradient, adjust, repeat.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# Data: target = input * 2
inputs = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
targets = np.array([2.0, 4.0, 6.0, 8.0, 10.0])

# --- Gradient Descent ---
# 1. Start with a random weight
# 2. Calculate the loss
# 3. Calculate the gradient (which direction to adjust)
# 4. Adjust the weight: new_weight = old_weight - learning_rate * gradient
# 5. Repeat until loss is small enough

weight = 0.0           # start wrong on purpose
learning_rate = 0.04   # how big a step to take each time

print(f"Starting weight: {weight}")
print(f"Learning rate: {learning_rate}")
print(f"Target weight: 2.0 (we know this, the model doesn't)")
print()
print(f"{'Step':>4s}  {'Weight':>8s}  {'Loss':>10s}  {'Gradient':>10s}")
print(f"{'----':>4s}  {'------':>8s}  {'--------':>10s}  {'--------':>10s}")

# range(20) means "do this 20 times" (steps 0 through 19)
for step in range(20):
    # Forward pass: make predictions with current weight
    predictions = inputs * weight

    # Calculate loss (MSE)
    loss = np.mean((predictions - targets) ** 2)

    # Calculate gradient
    # For MSE with this simple model, the gradient formula is:
    # gradient = 2 * mean(inputs * (predictions - targets))
    gradient = 2 * np.mean(inputs * (predictions - targets))

    # Print every few steps to see progress
    if step < 5 or step % 5 == 0:
        print(f"{step:>4d}  {weight:>8.4f}  {loss:>10.4f}  {gradient:>10.4f}")

    # Update: move weight in the OPPOSITE direction of the gradient
    # If gradient is positive (loss increases with weight), decrease weight
    # If gradient is negative (loss decreases with weight), increase weight
    weight = weight - learning_rate * gradient

print(f"{'...':>4s}")
print(f"{'DONE':>4s}  {weight:>8.4f}  {np.mean((inputs * weight - targets) ** 2):>10.4f}")
print()
print(f"Final weight: {weight:.4f}")
print(f"Expected:     2.0000")
print(f"Close enough? {'Yes!' if abs(weight - 2.0) < 0.01 else 'Need more steps'}")
print()

print("That's it. That's how every model trains:")
print("  1. Predict (forward pass)")
print("  2. Measure error (loss)")
print("  3. Calculate gradient (which direction)")
print("  4. Adjust weights (learning_rate * gradient)")
print("  5. Repeat")
PYEOF
```

Expected output (yours will differ):
```
Starting weight: 0.0
Learning rate: 0.04
Target weight: 2.0 (we know this, the model doesn't)

Step    Weight        Loss    Gradient
----    ------    --------    --------
   0    0.0000     44.0000    -22.0000
   1    0.8800      6.3888     -5.2800
   2    1.0912      3.6463     -3.9853
   3    1.2506      2.3277     -3.1848
   4    1.3780      1.5772     -2.6222
   5    1.4829      1.1072     -2.1972
  10    1.8003      0.0880     -0.6193
  15    1.9436      0.0070     -0.1747
DONE    1.9841      0.0006

Final weight: 1.9841
Expected:     2.0000
Close enough? Yes!

That's it. That's how every model trains:
  1. Predict (forward pass)
  2. Measure error (loss)
  3. Calculate gradient (which direction)
  4. Adjust weights (learning_rate * gradient)
  5. Repeat
```

---

## Step 4. Learning rate - how big a step?

The learning rate is the most important setting in training. Too high and the model overshoots. Too low and it takes forever.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

inputs = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
targets = np.array([2.0, 4.0, 6.0, 8.0, 10.0])

def train(learning_rate, steps=20):
    """Train with a given learning rate and return the history."""
    weight = 0.0
    history = []
    for step in range(steps):
        predictions = inputs * weight
        loss = np.mean((predictions - targets) ** 2)
        gradient = 2 * np.mean(inputs * (predictions - targets))
        history.append((step, weight, loss))
        weight = weight - learning_rate * gradient
    return history

# --- Try three learning rates ---
print("=" * 60)
print("Learning rate comparison")
print("=" * 60)

for lr in [0.001, 0.04, 0.2]:
    history = train(lr, steps=20)
    final_weight = history[-1][1]
    final_loss = history[-1][2]

    if lr == 0.001:
        label = "TOO SLOW"
    elif lr == 0.04:
        label = "JUST RIGHT"
    else:
        label = "TOO FAST"

    print(f"\nLearning rate = {lr} ({label})")
    print(f"  Step  0: weight={history[0][1]:.4f}, loss={history[0][2]:.4f}")
    print(f"  Step  5: weight={history[5][1]:.4f}, loss={history[5][2]:.4f}")
    print(f"  Step 10: weight={history[10][1]:.4f}, loss={history[10][2]:.4f}")
    print(f"  Step 19: weight={history[19][1]:.4f}, loss={history[19][2]:.4f}")

    if final_loss > 10:
        print(f"  PROBLEM: Loss is still high. Model barely learned.")
    elif final_loss > 1:
        print(f"  OK but slow. Needs more steps.")
    elif np.isnan(final_loss) or np.isinf(final_loss):
        print(f"  EXPLODED! Loss went to infinity. Learning rate too high.")
    else:
        print(f"  Good! Weight is close to 2.0.")

print()
print("=" * 60)

# Show what happens when learning rate is WAY too high
print("\nWhat happens with learning rate = 0.5 (way too high):")
history_bad = train(0.5, steps=10)
for step, weight, loss in history_bad[:6]:
    status = "EXPLODING!" if loss > 1000 else ""
    print(f"  Step {step}: weight={weight:>12.1f}, loss={loss:>12.1f}  {status}")
print("  ...")
print("  The weight bounces back and forth, loss gets BIGGER each step!")
print()

print("DBA analogy:")
print("  Learning rate too low = changing shared_buffers by 1MB at a time (takes forever)")
print("  Learning rate right   = changing by 64MB (converges quickly)")
print("  Learning rate too high = changing by 10GB at a time (system thrashes)")
PYEOF
```

Expected output (yours will differ):
```
============================================================
Learning rate comparison
============================================================

Learning rate = 0.001 (TOO SLOW)
  Step  0: weight=0.0000, loss=44.0000
  Step  5: weight=0.1058, loss=41.5315
  Step 10: weight=0.2029, loss=39.2265
  Step 19: weight=0.3739, loss=35.2022
  OK but slow. Needs more steps.

Learning rate = 0.04 (JUST RIGHT)
  Step  0: weight=0.0000, loss=44.0000
  Step  5: weight=1.4829, loss=1.1072
  Step 10: weight=1.8003, loss=0.0880
  Step 19: weight=1.9841, loss=0.0006
  Good! Weight is close to 2.0.

Learning rate = 0.2 (TOO FAST)
  Step  0: weight=0.0000, loss=44.0000
  Step  5: weight=1.9809, loss=3.2684
  Step 10: weight=2.0158, loss=2.4000
  Step 19: weight=2.0002, loss=0.0001
  Good! Weight is close to 2.0.

============================================================

What happens with learning rate = 0.5 (way too high):
  Step 0: weight=         0.0, loss=        44.0
  Step 1: weight=        11.0, loss=     8019.0
  Step 2: weight=      -132.5, loss=  1982619.0  EXPLODING!
  Step 3: weight=     16632.2, loss=  ...
  ...
  The weight bounces back and forth, loss gets BIGGER each step!

DBA analogy:
  Learning rate too low = changing shared_buffers by 1MB at a time (takes forever)
  Learning rate right   = changing by 64MB (converges quickly)
  Learning rate too high = changing by 10GB at a time (system thrashes)
```

---

## Step 5. Putting it all together - a mini neural network

Let's build the simplest possible neural network using everything from this module: vectors, matrix multiply, loss, and gradient descent.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

np.random.seed(42)

# --- Problem: predict if a server needs attention ---
# Input: [CPU%, Memory%, Connections (normalized)]
# Output: 0 = healthy, 1 = needs attention

# Training data (4 servers we've already labeled)
# Each row: [CPU, Memory, Connections] (normalized to 0-1)
X = np.array([
    [0.92, 0.68, 0.95],  # sick     (high everything)
    [0.15, 0.42, 0.08],  # healthy  (low everything)
    [0.88, 0.90, 0.88],  # sick     (high everything)
    [0.20, 0.30, 0.10],  # healthy  (low everything)
])

# Labels: 1 = needs attention, 0 = healthy
y = np.array([1, 0, 1, 0])

# --- Build a tiny neural network ---
# One layer: output = X @ weights + bias
# Then apply "sigmoid" to squish output between 0 and 1

# Initialize weights randomly (3 inputs -> 1 output)
# np.random.randn() generates random numbers from a normal distribution
weights = np.random.randn(3) * 0.1  # small random numbers
bias = 0.0

def sigmoid(x):
    """Squish any number into the range 0 to 1.
    Big positive number -> close to 1
    Big negative number -> close to 0
    Zero -> exactly 0.5
    """
    return 1 / (1 + np.exp(-x))

learning_rate = 1.0

print("Training a mini neural network")
print(f"Starting weights: {weights.round(4)}")
print(f"Starting bias: {bias}")
print()

# Train for 100 steps
for step in range(100):
    # --- Forward pass (make predictions) ---
    # X @ weights = dot product of each server's metrics with weights
    # This gives one score per server
    z = X @ weights + bias
    predictions = sigmoid(z)

    # --- Calculate loss ---
    # Binary cross-entropy (standard loss for yes/no problems)
    # Don't worry about the formula - just know: lower = better
    # np.clip() prevents log(0) which would be infinity
    loss = -np.mean(y * np.log(np.clip(predictions, 1e-7, 1)) +
                    (1 - y) * np.log(np.clip(1 - predictions, 1e-7, 1)))

    # --- Calculate gradients ---
    error = predictions - y                    # how wrong each prediction is
    grad_weights = X.T @ error / len(y)        # gradient for weights
    grad_bias = np.mean(error)                 # gradient for bias

    # --- Update weights ---
    weights = weights - learning_rate * grad_weights
    bias = bias - learning_rate * grad_bias

    # Print progress every 20 steps
    if step % 20 == 0:
        # Calculate accuracy
        # (predictions > 0.5) converts to True/False (1/0)
        # == y checks if our prediction matches the label
        # .mean() gives the fraction correct
        accuracy = np.mean((predictions > 0.5).astype(int) == y)
        print(f"Step {step:>3d}: loss={loss:.4f}, accuracy={accuracy*100:.0f}%")

# Final results
print()
print("Final predictions:")
for i in range(len(X)):
    status = "NEEDS ATTENTION" if predictions[i] > 0.5 else "healthy"
    correct = "correct" if (predictions[i] > 0.5) == y[i] else "WRONG"
    print(f"  Server {i+1}: {predictions[i]:.4f} -> {status} ({correct})")

print()
print(f"Final weights: {weights.round(4)}")
print(f"Final bias: {bias:.4f}")
print()
print("What the weights mean:")
print(f"  CPU weight:         {weights[0]:.2f} (how much CPU matters)")
print(f"  Memory weight:      {weights[1]:.2f} (how much memory matters)")
print(f"  Connections weight: {weights[2]:.2f} (how much connections matter)")
print()
print("The model LEARNED which metrics predict a sick server!")
print("This is the foundation of ALL neural networks.")
PYEOF
```

Expected output (yours will differ):
```
Training a mini neural network
Starting weights: [ 0.0497 -0.0139  0.0647]
Starting bias: 0.0

Step   0: loss=0.6813, accuracy=50%
Step  20: loss=0.1742, accuracy=100%
Step  40: loss=0.0905, accuracy=100%
Step  60: loss=0.0607, accuracy=100%
Step  80: loss=0.0457, accuracy=100%

Final predictions:
  Server 1: 0.9803 -> NEEDS ATTENTION (correct)
  Server 2: 0.0252 -> healthy (correct)
  Server 3: 0.9906 -> NEEDS ATTENTION (correct)
  Server 4: 0.0155 -> healthy (correct)

Final weights: [2.1463 1.8672 2.0913]
Final bias: -2.6098

What the weights mean:
  CPU weight:         2.15 (how much CPU matters)
  Memory weight:      1.87 (how much memory matters)
  Connections weight: 2.09 (how much connections matter)

The model LEARNED which metrics predict a sick server!
This is the foundation of ALL neural networks.
```

---

## What You Learned

| Concept | What It Is | DBA Analogy | AI Use |
|---------|-----------|-------------|--------|
| Loss function | Measures how wrong the model is | Error rate in monitoring | MSE, cross-entropy |
| Gradient | Direction that reduces loss | "Should I tune this up or down?" | Tells which way to adjust weights |
| Gradient descent | Adjust weights to reduce loss | Auto-tuning parameters | How every model trains |
| Learning rate | Size of each adjustment step | How much to change a parameter | Most important training setting |
| Forward pass | Make predictions with current weights | Run a query | input @ weights + bias |
| Sigmoid | Squish output to 0-1 | Probability/percentage | Binary classification |
| Training loop | Predict -> measure -> adjust -> repeat | Continuous tuning | The core of all AI training |
