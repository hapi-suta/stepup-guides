# SURVIVE 01: Vanishing Gradients

Your deep neural network trains but the loss barely moves. The model learns nothing no matter how long you train. The gradients are vanishing - becoming so small they're effectively zero.

---

## The Scenario

A junior engineer built a 10-layer neural network using sigmoid activations everywhere. It trains for 100 epochs and the loss barely decreases. The same architecture with ReLU activations works fine.

---

## Step 1. See the problem

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

np.random.seed(42)
torch.manual_seed(42)

# Simple data
n = 500
X_np = np.random.uniform(0, 1, (n, 5)).astype(np.float32)
y_np = (X_np[:, 0] > 0.5).astype(np.float32)
X = torch.tensor(X_np)
y = torch.tensor(y_np).reshape(-1, 1)

# --- Deep network with SIGMOID activations (broken) ---
model_sigmoid = nn.Sequential(
    nn.Linear(5, 32), nn.Sigmoid(),
    nn.Linear(32, 32), nn.Sigmoid(),
    nn.Linear(32, 32), nn.Sigmoid(),
    nn.Linear(32, 32), nn.Sigmoid(),
    nn.Linear(32, 32), nn.Sigmoid(),
    nn.Linear(32, 1), nn.Sigmoid(),
)

# --- Same network with RELU activations (works) ---
model_relu = nn.Sequential(
    nn.Linear(5, 32), nn.ReLU(),
    nn.Linear(32, 32), nn.ReLU(),
    nn.Linear(32, 32), nn.ReLU(),
    nn.Linear(32, 32), nn.ReLU(),
    nn.Linear(32, 32), nn.ReLU(),
    nn.Linear(32, 1), nn.Sigmoid(),  # only output uses sigmoid
)

def train_model(model, name, epochs=80):
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    loss_fn = nn.BCELoss()
    losses = []

    for epoch in range(epochs):
        pred = model(X[:400])
        loss = loss_fn(pred, y[:400])
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        losses.append(loss.item())

    model.eval()
    with torch.no_grad():
        acc = ((model(X[400:]) > 0.5).float() == y[400:]).float().mean()

    print(f"\n{name}:")
    print(f"  Loss at start:  {losses[0]:.4f}")
    print(f"  Loss at epoch 20: {losses[19]:.4f}")
    print(f"  Loss at end:    {losses[-1]:.4f}")
    print(f"  Test accuracy:  {acc.item():.1%}")

    # Check gradient magnitudes in the FIRST layer
    # If gradients are tiny, the first layers aren't learning
    pred = model(X[:400])
    loss = loss_fn(pred, y[:400])
    loss.backward()

    first_layer = list(model.parameters())[0]
    grad_magnitude = first_layer.grad.abs().mean().item()
    print(f"  First layer gradient magnitude: {grad_magnitude:.6f}")

    if grad_magnitude < 0.0001:
        print(f"  VANISHING! Gradient is nearly zero. First layers aren't learning.")
    else:
        print(f"  OK. Gradients are flowing through the network.")

train_model(model_sigmoid, "Deep Sigmoid (BROKEN)")
train_model(model_relu, "Deep ReLU (WORKS)")
PYEOF
```

Expected output (yours will differ):
```
Deep Sigmoid (BROKEN):
  Loss at start:  0.6975
  Loss at epoch 20: 0.6932
  Loss at end:    0.6885
  Test accuracy:  55.0%
  First layer gradient magnitude: 0.000023
  VANISHING! Gradient is nearly zero. First layers aren't learning.

Deep ReLU (WORKS):
  Loss at start:  0.7134
  Loss at epoch 20: 0.2145
  Loss at end:    0.0312
  Test accuracy:  98.0%
  First layer gradient magnitude: 0.001245
  OK. Gradients are flowing through the network.
```

---

## Step 2. Understand why sigmoid causes vanishing gradients

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
Why sigmoid causes vanishing gradients:

Sigmoid function: sigmoid(x) = 1 / (1 + exp(-x))

The GRADIENT of sigmoid is: sigmoid(x) * (1 - sigmoid(x))

Maximum gradient: when x=0, sigmoid=0.5, gradient = 0.5 * 0.5 = 0.25
That means: even in the BEST case, each sigmoid layer multiplies
the gradient by at most 0.25.

With 6 sigmoid layers:
  Gradient at layer 1 = original_gradient * 0.25 * 0.25 * 0.25 * 0.25 * 0.25 * 0.25
                       = original_gradient * 0.000244
  That's 4,000x smaller!

The first layers receive almost zero gradient, so they can't learn.
""")

# Demonstrate
sigmoid = nn.Sigmoid()
x = torch.tensor([0.0])  # best case for sigmoid gradient
sig_val = sigmoid(x)
gradient = sig_val * (1 - sig_val)
print(f"Sigmoid at x=0:     {sig_val.item():.4f}")
print(f"Max gradient:       {gradient.item():.4f}")
print()

# After 6 layers, gradient is multiplied by 0.25 six times
grad_after_6 = 0.25 ** 6
print(f"After 6 sigmoid layers: {grad_after_6:.6f}")
print(f"That's {1/grad_after_6:.0f}x smaller than the original!")
print()

print("ReLU doesn't have this problem:")
print("  ReLU gradient is 1 for positive values, 0 for negative")
print("  Positive inputs pass gradients through unchanged (multiplied by 1)")
print("  No shrinking, no vanishing")
PYEOF
```

---

## Step 3. The fix

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Vanishing Gradient Fixes:

1. USE ReLU for hidden layers (not sigmoid)
   - Sigmoid: gradient shrinks at every layer (max 0.25)
   - ReLU: gradient is 1 for positive values (no shrinking)
   - ONLY use sigmoid at the final output for binary classification

2. USE proper weight initialization
   PyTorch does this by default (Kaiming initialization for ReLU)
   If you initialize weights too large or too small, gradients can
   vanish or explode from the start

3. USE batch normalization
   nn.BatchNorm1d(n) normalizes layer outputs to mean=0, std=1
   This keeps values in a good range for gradient flow

4. USE residual connections (skip connections)
   Instead of: output = layer(input)
   Use:        output = layer(input) + input
   The gradient flows through the skip connection even if the
   layer gradient vanishes. This is how very deep networks work.

Correct architecture:
  nn.Sequential(
      nn.Linear(5, 32),
      nn.BatchNorm1d(32),    # normalize after linear
      nn.ReLU(),             # ReLU, not sigmoid
      nn.Dropout(0.2),       # prevent overfitting
      nn.Linear(32, 32),
      nn.BatchNorm1d(32),
      nn.ReLU(),
      nn.Linear(32, 1),
      nn.Sigmoid(),          # sigmoid ONLY at the output
  )

Rules:
  Hidden layers: ReLU (or LeakyReLU, GELU)
  Output layer (binary): Sigmoid
  Output layer (multi-class): no activation (CrossEntropyLoss adds softmax)
  Optional: BatchNorm after Linear, before ReLU
""")
PYEOF
```

---

## What You Learned

| Problem | Cause | Fix |
|---------|-------|-----|
| Loss barely decreases | Vanishing gradients | Use ReLU, not sigmoid, for hidden layers |
| First layers don't learn | Sigmoid max gradient = 0.25 per layer | ReLU passes gradient = 1.0 |
| Very deep network won't train | Gradient shrinks exponentially | Add BatchNorm, residual connections |
| All predictions are 0.5 | Model can't learn useful features | Check gradient magnitude in first layer |
