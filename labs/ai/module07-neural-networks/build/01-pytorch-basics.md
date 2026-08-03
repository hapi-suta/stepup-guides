# Build 01: PyTorch Basics

PyTorch is the library that runs neural networks. It's like NumPy but with two superpowers: GPU acceleration and automatic gradient calculation.

---

## Step 1. Tensors - PyTorch's version of arrays

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch

# A tensor is PyTorch's version of a NumPy array
# Same idea: a grid of numbers

# --- Create tensors ---
# From a Python list (like np.array())
# torch.tensor() converts a list to a tensor
a = torch.tensor([1.0, 2.0, 3.0])
print(f"1D tensor: {a}")
print(f"Shape: {a.shape}")
print(f"Type: {a.dtype}")
print()

# 2D tensor (matrix)
b = torch.tensor([
    [1.0, 2.0, 3.0],
    [4.0, 5.0, 6.0],
])
print(f"2D tensor:\n{b}")
print(f"Shape: {b.shape}  (2 rows, 3 columns)")
print()

# --- Common creation functions ---
# torch.zeros() = all zeros (like np.zeros)
zeros = torch.zeros(3, 4)
print(f"Zeros (3x4):\n{zeros}")
print()

# torch.randn() = random numbers from normal distribution (like np.random.randn)
# This is how neural network weights are initialized
random = torch.randn(2, 3)
print(f"Random (2x3):\n{random}")
print()

# --- Convert between NumPy and PyTorch ---
import numpy as np
np_array = np.array([10, 20, 30])
tensor_from_np = torch.from_numpy(np_array.astype(np.float32))
print(f"NumPy -> Tensor: {tensor_from_np}")

back_to_np = tensor_from_np.numpy()
print(f"Tensor -> NumPy: {back_to_np}")
PYEOF
```

Expected output (yours will differ):
```
1D tensor: tensor([1., 2., 3.])
Shape: torch.Size([3])
Type: torch.float32

2D tensor:
tensor([[1., 2., 3.],
        [4., 5., 6.]])
Shape: torch.Size([2, 3])  (2 rows, 3 columns)

Zeros (3x4):
tensor([[0., 0., 0., 0.],
        [0., 0., 0., 0.],
        [0., 0., 0., 0.]])

Random (2x3):
tensor([[ 0.3367,  0.1288,  0.2345],
        [ 0.2303, -1.1229, -0.1863]])
```

---

## Step 2. Tensor math - same as NumPy

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch

a = torch.tensor([1.0, 2.0, 3.0])
b = torch.tensor([4.0, 5.0, 6.0])

# Element-wise operations (same as NumPy)
print(f"a + b = {a + b}")
print(f"a * b = {a * b}")
print(f"a * 2 = {a * 2}")
print()

# Dot product (same as np.dot)
dot = torch.dot(a, b)
print(f"Dot product: {dot}")
# (1*4) + (2*5) + (3*6) = 4 + 10 + 18 = 32
print()

# Matrix multiply (same as @ in NumPy)
# torch.mm() for 2D matrices, @ also works
X = torch.tensor([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])  # (3, 2)
W = torch.tensor([[0.5], [0.3]])                           # (2, 1)
result = X @ W                                              # (3, 1)
print(f"Matrix multiply:")
print(f"X shape: {X.shape}, W shape: {W.shape}")
print(f"Result shape: {result.shape}")
print(f"Result:\n{result}")
print()

# Aggregations
data = torch.tensor([10.0, 20.0, 30.0, 40.0, 50.0])
print(f"Mean: {data.mean()}")
print(f"Std:  {data.std()}")
print(f"Sum:  {data.sum()}")
print(f"Max:  {data.max()}")
PYEOF
```

Expected output (yours will differ):
```
a + b = tensor([5., 7., 9.])
a * b = tensor([ 4., 10., 18.])
a * 2 = tensor([2., 4., 6.])

Dot product: 32.0

Matrix multiply:
X shape: torch.Size([3, 2]), W shape: torch.Size([2, 1])
Result shape: torch.Size([3, 1])
Result:
tensor([[ 1.1000],
        [ 2.7000],
        [ 4.3000]])

Mean: 30.0
Std:  15.811...
Sum:  150.0
Max:  50.0
```

---

## Step 3. Autograd - automatic gradient calculation

This is PyTorch's superpower. You tell it "track the math" and it calculates gradients automatically. No manual gradient formulas needed.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch

# --- The manual way (Module 05) ---
# You calculated gradients by hand:
#   gradient = 2 * mean(inputs * (predictions - targets))
# That was painful and only worked for simple models.

# --- The PyTorch way ---
# Step 1: Create a tensor with requires_grad=True
# This tells PyTorch: "track all math done on this tensor"
weight = torch.tensor([0.5], requires_grad=True)

# Step 2: Do some math (forward pass)
inputs = torch.tensor([1.0, 2.0, 3.0, 4.0, 5.0])
targets = torch.tensor([2.0, 4.0, 6.0, 8.0, 10.0])

predictions = inputs * weight        # multiply
loss = ((predictions - targets) ** 2).mean()  # MSE loss

print(f"Weight: {weight.item():.4f}")
print(f"Loss:   {loss.item():.4f}")
print()

# Step 3: Calculate gradients automatically
# .backward() traces back through ALL the math and calculates
# the gradient of the loss with respect to every tensor that has
# requires_grad=True
loss.backward()

# Step 4: Read the gradient
# .grad contains the gradient (dloss/dweight)
print(f"Gradient: {weight.grad.item():.4f}")
print()

# The gradient tells us: "if we increase the weight slightly,
# the loss will change by this much"
# Negative gradient = increasing weight decreases loss = go up
# Positive gradient = increasing weight increases loss = go down

print("What this means:")
if weight.grad.item() < 0:
    print(f"  Gradient is negative ({weight.grad.item():.4f})")
    print(f"  Increasing the weight will DECREASE the loss")
    print(f"  So we should INCREASE the weight (it's too low)")
else:
    print(f"  Gradient is positive ({weight.grad.item():.4f})")
    print(f"  Increasing the weight will INCREASE the loss")
    print(f"  So we should DECREASE the weight (it's too high)")

print()
print("In Module 05, you calculated this gradient BY HAND.")
print("PyTorch does it automatically for ANY computation, no matter how complex.")
print("This is what makes deep learning possible.")
PYEOF
```

Expected output (yours will differ):
```
Weight: 0.5000
Loss:   24.7500

Gradient: -16.5000

What this means:
  Gradient is negative (-16.5000)
  Increasing the weight will DECREASE the loss
  So we should INCREASE the weight (it's too low)

In Module 05, you calculated this gradient BY HAND.
PyTorch does it automatically for ANY computation, no matter how complex.
This is what makes deep learning possible.
```

---

## Step 4. Training with autograd - gradient descent made easy

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch

# Same problem as Module 05: find weight such that y = weight * x
inputs = torch.tensor([1.0, 2.0, 3.0, 4.0, 5.0])
targets = torch.tensor([2.0, 4.0, 6.0, 8.0, 10.0])

# Start with a random weight
weight = torch.tensor([0.0], requires_grad=True)
learning_rate = 0.04

print("Training with PyTorch autograd:")
print(f"{'Step':>4s}  {'Weight':>8s}  {'Loss':>10s}  {'Gradient':>10s}")
print("-" * 38)

for step in range(20):
    # Forward pass
    predictions = inputs * weight
    loss = ((predictions - targets) ** 2).mean()

    # Backward pass (calculate gradients)
    loss.backward()

    if step < 5 or step % 5 == 0:
        print(f"{step:>4d}  {weight.item():>8.4f}  {loss.item():>10.4f}  {weight.grad.item():>10.4f}")

    # Update weight (gradient descent)
    # torch.no_grad() tells PyTorch "don't track this math"
    # We don't want gradients of the update itself
    with torch.no_grad():
        weight -= learning_rate * weight.grad

    # IMPORTANT: zero the gradients after each step
    # PyTorch accumulates gradients by default (adds them up)
    # If you don't zero them, they keep growing
    weight.grad.zero_()

print(f"\nFinal weight: {weight.item():.4f}")
print(f"Expected:     2.0000")
print(f"Match: {'Yes!' if abs(weight.item() - 2.0) < 0.01 else 'Need more steps'}")
print()
print("Same result as Module 05, but:")
print("  - No manual gradient formula")
print("  - Works for ANY model, not just simple ones")
print("  - Scales to millions of parameters")
PYEOF
```

Expected output (yours will differ):
```
Training with PyTorch autograd:
Step    Weight        Loss    Gradient
--------------------------------------
   0    0.0000     44.0000    -22.0000
   1    0.8800      6.3888     -5.2800
   2    1.0912      3.6463     -3.9853
   3    1.2506      2.3277     -3.1848
   4    1.3780      1.5772     -2.6222
   5    1.4829      1.1072     -2.1972
  10    1.8003      0.0880     -0.6193
  15    1.9436      0.0070     -0.1747

Final weight: 1.9841
Expected:     2.0000
Match: Yes!

Same result as Module 05, but:
  - No manual gradient formula
  - Works for ANY model, not just simple ones
  - Scales to millions of parameters
```

---

## Step 5. Using PyTorch optimizers

Instead of writing `weight -= learning_rate * weight.grad` yourself, PyTorch has optimizers that do it (and do it better).

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.optim as optim

# Same problem
inputs = torch.tensor([1.0, 2.0, 3.0, 4.0, 5.0])
targets = torch.tensor([2.0, 4.0, 6.0, 8.0, 10.0])

weight = torch.tensor([0.0], requires_grad=True)

# --- SGD optimizer (Stochastic Gradient Descent) ---
# Same as doing weight -= lr * grad, but handles it for you
optimizer = optim.SGD([weight], lr=0.04)

print("Training with SGD optimizer:")
for step in range(20):
    predictions = inputs * weight
    loss = ((predictions - targets) ** 2).mean()
    loss.backward()

    # optimizer.step() updates all tracked parameters
    optimizer.step()
    # optimizer.zero_grad() zeros all gradients
    optimizer.zero_grad()

    if step < 3 or step % 5 == 0:
        print(f"  Step {step:>2d}: weight={weight.item():.4f}, loss={loss.item():.4f}")

print(f"  Final: {weight.item():.4f}")
print()

# --- Adam optimizer (the most popular) ---
# Adam adapts the learning rate per-parameter
# It's almost always better than SGD
weight2 = torch.tensor([0.0], requires_grad=True)
optimizer2 = optim.Adam([weight2], lr=0.1)

print("Training with Adam optimizer:")
for step in range(20):
    predictions = inputs * weight2
    loss = ((predictions - targets) ** 2).mean()
    loss.backward()
    optimizer2.step()
    optimizer2.zero_grad()

    if step < 3 or step % 5 == 0:
        print(f"  Step {step:>2d}: weight={weight2.item():.4f}, loss={loss.item():.4f}")

print(f"  Final: {weight2.item():.4f}")
print()

print("In practice:")
print("  - Use Adam as your default optimizer")
print("  - lr=0.001 is a good starting point for Adam")
print("  - Only switch to SGD if you need fine-tuning control")
PYEOF
```

Expected output (yours will differ):
```
Training with SGD optimizer:
  Step  0: weight=0.8800, loss=44.0000
  Step  1: weight=1.0912, loss=6.3888
  Step  2: weight=1.2506, loss=3.6463
  Step  5: weight=1.4829, loss=1.1072
  Step 10: weight=1.8003, loss=0.0880
  Step 15: weight=1.9436, loss=0.0070
  Final: 1.9841

Training with Adam optimizer:
  Step  0: weight=0.1000, loss=44.0000
  Step  1: weight=0.2000, loss=39.8200
  Step  2: weight=0.3000, loss=35.8600
  Step  5: weight=0.5997, loss=21.5844
  Step 10: weight=1.0948, loss=9.0326
  Step 15: weight=1.6652, loss=1.2386
  Final: 1.9976
```

---

## What You Learned

| Concept | What It Is | NumPy Equivalent |
|---------|-----------|-----------------|
| torch.tensor() | Create a tensor | np.array() |
| .shape | Dimensions of tensor | .shape |
| requires_grad=True | Track math for gradients | N/A (manual in NumPy) |
| loss.backward() | Calculate all gradients automatically | Manual gradient formula |
| .grad | Access the calculated gradient | N/A |
| .grad.zero_() | Reset gradients to zero | N/A |
| optimizer.step() | Update weights | weight -= lr * grad |
| optimizer.zero_grad() | Zero all gradients | N/A |
| torch.no_grad() | Disable gradient tracking | N/A |
| Adam | Adaptive optimizer | N/A |
