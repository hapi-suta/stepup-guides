# Build 02: Your First Neural Network

In Module 05, you built a single-layer network with NumPy. Now you'll build a multi-layer network with PyTorch. More layers = the model can learn more complex patterns.

---

## Step 1. What is a layer?

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

# nn.Linear is a single layer
# It does: output = input @ weights + bias
# Same as Module 05, but PyTorch manages the weights for you

# nn.Linear(in_features, out_features)
#   in_features = how many numbers go IN
#   out_features = how many numbers come OUT

# Example: 3 inputs (CPU, Memory, Connections) -> 1 output (health score)
layer = nn.Linear(3, 1)

print("A single layer:")
print(f"  Input size:  3 (CPU, Memory, Connections)")
print(f"  Output size: 1 (health score)")
print()

# The layer has weights and a bias (randomly initialized)
# .weight and .bias show what the layer starts with
print(f"  Weights: {layer.weight.data}")
print(f"  Bias:    {layer.bias.data}")
print()

# Pass data through the layer
# The input must be a tensor with 3 numbers (matching in_features=3)
server = torch.tensor([0.92, 0.68, 0.95])  # CPU=92%, Mem=68%, Conn=95%
output = layer(server)  # calling the layer like a function runs the math
print(f"  Input:  {server}")
print(f"  Output: {output.item():.4f}")
print()
print("  That output is: (0.92 * w1) + (0.68 * w2) + (0.95 * w3) + bias")
print("  The weights are random right now. Training will make them useful.")
PYEOF
```

Expected output (yours will differ):
```
A single layer:
  Input size:  3 (CPU, Memory, Connections)
  Output size: 1 (health score)

  Weights: tensor([[ 0.2975, -0.2548, -0.1119]])
  Bias:    tensor([0.0897])

  Input:  tensor([0.92, 0.68, 0.95])
  Output: 0.0958

  That output is: (0.92 * w1) + (0.68 * w2) + (0.95 * w3) + bias
  The weights are random right now. Training will make them useful.
```

---

## Step 2. Stack layers into a network

A neural network is just layers stacked on top of each other. Data flows through each layer in order.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

# --- Build a 3-layer network ---
# nn.Sequential stacks layers in order
# Data flows: input -> layer1 -> activation -> layer2 -> activation -> layer3 -> output

model = nn.Sequential(
    nn.Linear(3, 8),     # Layer 1: 3 inputs -> 8 hidden neurons
    nn.ReLU(),           # Activation: turns negative numbers to 0
    nn.Linear(8, 4),     # Layer 2: 8 -> 4 hidden neurons
    nn.ReLU(),           # Activation again
    nn.Linear(4, 1),     # Layer 3: 4 -> 1 output
    nn.Sigmoid(),        # Sigmoid: squishes output to 0-1 (probability)
)

print("Neural Network Architecture:")
print(model)
print()

# Count parameters (weights + biases)
# sum(p.numel() for p in model.parameters()) counts ALL numbers the model learns
total_params = sum(p.numel() for p in model.parameters())
print(f"Total parameters: {total_params}")
print()

# Break it down layer by layer
print("Parameter count per layer:")
for name, param in model.named_parameters():
    print(f"  {name:20s} shape={str(param.shape):15s} params={param.numel()}")
# Layer 1: 3*8 weights + 8 biases = 32
# Layer 2: 8*4 weights + 4 biases = 36
# Layer 3: 4*1 weights + 1 bias = 5
# Total: 73
print()

# Pass data through the entire network
server = torch.tensor([0.92, 0.68, 0.95])
prediction = model(server)
print(f"Input:  {server}")
print(f"Output: {prediction.item():.4f}")
print(f"  (this is a probability: 0=healthy, 1=incident)")
print()

print("What happened:")
print("  [0.92, 0.68, 0.95]")
print("       |")
print("  Layer 1 (3->8): multiply by 24 weights, add 8 biases")
print("  ReLU: set negative values to 0")
print("       |")
print("  Layer 2 (8->4): multiply by 32 weights, add 4 biases")
print("  ReLU: set negative values to 0")
print("       |")
print("  Layer 3 (4->1): multiply by 4 weights, add 1 bias")
print("  Sigmoid: squish to 0-1")
print("       |")
print(f"  Output: {prediction.item():.4f}")
PYEOF
```

Expected output (yours will differ):
```
Neural Network Architecture:
Sequential(
  (0): Linear(in_features=3, out_features=8, bias=True)
  (1): ReLU()
  (2): Linear(in_features=8, out_features=4, bias=True)
  (3): ReLU()
  (4): Linear(in_features=4, out_features=1, bias=True)
  (5): Sigmoid()
)

Total parameters: 73
...
```

---

## Step 3. Train the network

Now let's train this network to predict server incidents. Same gradient descent concept as Module 05, but PyTorch handles the hard parts.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

# --- Create training data ---
np.random.seed(42)
n = 300

cpu = np.random.uniform(0, 1, n)          # already normalized 0-1
memory = np.random.uniform(0, 1, n)
connections = np.random.uniform(0, 1, n)

# Incident if high CPU AND high connections, or very high memory
incident = ((cpu > 0.7) & (connections > 0.7) |
            (memory > 0.9)).astype(np.float32)

# Convert to PyTorch tensors
# torch.tensor() needs float32 for neural networks
X = torch.tensor(np.column_stack([cpu, memory, connections]), dtype=torch.float32)
y = torch.tensor(incident, dtype=torch.float32).reshape(-1, 1)
# reshape(-1, 1) makes y a column vector: [[0], [1], [0], ...]
# The model outputs shape (n, 1), so y must match

# Train/test split (manual since we're using raw tensors)
split = int(0.8 * n)
X_train, X_test = X[:split], X[split:]
y_train, y_test = y[:split], y[split:]

print(f"Training: {X_train.shape[0]} samples")
print(f"Testing:  {X_test.shape[0]} samples")
print(f"Incidents: {int(y.sum())}/{n} ({y.mean()*100:.1f}%)")
print()

# --- Build the model ---
model = nn.Sequential(
    nn.Linear(3, 16),    # 3 inputs -> 16 hidden
    nn.ReLU(),
    nn.Linear(16, 8),    # 16 -> 8 hidden
    nn.ReLU(),
    nn.Linear(8, 1),     # 8 -> 1 output
    nn.Sigmoid(),
)

# Loss function: Binary Cross Entropy
# Standard loss for yes/no classification
# Measures how far the predicted probability is from the actual label
loss_fn = nn.BCELoss()

# Optimizer: Adam with learning rate 0.01
optimizer = optim.Adam(model.parameters(), lr=0.01)

# --- Training loop ---
print(f"{'Epoch':>5s}  {'Train Loss':>11s}  {'Test Loss':>10s}  {'Test Acc':>9s}")
print("-" * 40)

# An "epoch" is one pass through ALL the training data
for epoch in range(100):
    # --- Forward pass ---
    # Pass all training data through the model
    predictions = model(X_train)

    # Calculate loss
    loss = loss_fn(predictions, y_train)

    # --- Backward pass ---
    optimizer.zero_grad()  # reset gradients
    loss.backward()        # calculate new gradients
    optimizer.step()       # update weights

    # --- Evaluate every 10 epochs ---
    if epoch % 10 == 0 or epoch == 99:
        # torch.no_grad() disables gradient tracking (faster, saves memory)
        with torch.no_grad():
            test_pred = model(X_test)
            test_loss = loss_fn(test_pred, y_test)

            # Accuracy: how many predictions are correct?
            # (test_pred > 0.5) converts probabilities to 0/1
            # .float() converts True/False to 1.0/0.0
            accuracy = ((test_pred > 0.5).float() == y_test).float().mean()

        print(f"{epoch:>5d}  {loss.item():>11.4f}  {test_loss.item():>10.4f}  {accuracy.item():>8.1%}")

print()
print("The loss decreases over epochs = the model is learning!")
print("Test accuracy shows how well it works on data it never saw.")
PYEOF
```

Expected output (yours will differ):
```
Training: 240 samples
Testing:  60 samples
Incidents: 42/300 (14.0%)

Epoch  Train Loss   Test Loss   Test Acc
----------------------------------------
    0      0.7012      0.6924     53.3%
   10      0.4521      0.4389     88.3%
   20      0.2876      0.2812     93.3%
   30      0.1985      0.2041     95.0%
   40      0.1478      0.1621     95.0%
   50      0.1139      0.1368     96.7%
   60      0.0906      0.1217     96.7%
   70      0.0741      0.1125     96.7%
   80      0.0620      0.1071     96.7%
   90      0.0530      0.1038     96.7%
   99      0.0464      0.1024     96.7%

The loss decreases over epochs = the model is learning!
Test accuracy shows how well it works on data it never saw.
```

---

## Step 4. Understand activation functions

Without activation functions, stacking layers does nothing. ReLU is the most common - it simply turns negative numbers to zero.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

# --- Why do we need activation functions? ---
# Without them, two linear layers collapse into one:
#   layer1: y = x @ W1 + b1
#   layer2: z = y @ W2 + b2
#   Combined: z = x @ (W1 @ W2) + (b1 @ W2 + b2) = x @ W_combined + b_combined
# That's still just one linear layer! No benefit from stacking.
#
# Activation functions break this linearity.
# They let the network learn CURVES, not just straight lines.

values = torch.tensor([-3.0, -1.0, 0.0, 0.5, 1.0, 3.0])

# --- ReLU: Rectified Linear Unit ---
# If positive: keep it. If negative: set to 0.
# The most popular activation. Use it for hidden layers.
relu = nn.ReLU()
print("ReLU (most common for hidden layers):")
print(f"  Input:  {values.tolist()}")
print(f"  Output: {relu(values).tolist()}")
print(f"  Rule: max(0, x) - negatives become 0, positives stay")
print()

# --- Sigmoid ---
# Squishes any number to between 0 and 1.
# Use for binary classification output (probability).
sigmoid = nn.Sigmoid()
print("Sigmoid (for binary output):")
print(f"  Input:  {values.tolist()}")
print(f"  Output: {[round(x, 4) for x in sigmoid(values).tolist()]}")
print(f"  Rule: big negative -> ~0, big positive -> ~1, zero -> 0.5")
print()

# --- Softmax ---
# Like sigmoid but for MULTIPLE classes.
# Outputs sum to 1.0 (like probabilities).
softmax = nn.Softmax(dim=0)
scores = torch.tensor([2.0, 1.0, 0.5])
print("Softmax (for multi-class output):")
print(f"  Input (raw scores):  {scores.tolist()}")
print(f"  Output (probabilities): {[round(x, 4) for x in softmax(scores).tolist()]}")
print(f"  Sum: {softmax(scores).sum().item():.1f} (always sums to 1.0)")
print(f"  Highest score (2.0) gets highest probability")
print()

print("Summary:")
print("  Hidden layers: use ReLU (always)")
print("  Binary output (yes/no): use Sigmoid")
print("  Multi-class output (A/B/C): use Softmax")
PYEOF
```

Expected output (yours will differ):
```
ReLU (most common for hidden layers):
  Input:  [-3.0, -1.0, 0.0, 0.5, 1.0, 3.0]
  Output: [0.0, 0.0, 0.0, 0.5, 1.0, 3.0]
  Rule: max(0, x) - negatives become 0, positives stay

Sigmoid (for binary output):
  Input:  [-3.0, -1.0, 0.0, 0.5, 1.0, 3.0]
  Output: [0.0474, 0.2689, 0.5, 0.6225, 0.7311, 0.9526]
  Rule: big negative -> ~0, big positive -> ~1, zero -> 0.5

Softmax (for multi-class output):
  Input (raw scores):  [2.0, 1.0, 0.5]
  Output (probabilities): [0.5761, 0.2119, 0.1285]
  Sum: 1.0 (always sums to 1.0)
  Highest score (2.0) gets highest probability

Summary:
  Hidden layers: use ReLU (always)
  Binary output (yes/no): use Sigmoid
  Multi-class output (A/B/C): use Softmax
```

---

## What You Learned

| Concept | What It Is | Code |
|---------|-----------|------|
| nn.Linear(in, out) | One layer: input @ weights + bias | `nn.Linear(3, 8)` |
| nn.Sequential | Stack layers in order | `nn.Sequential(layer1, relu, layer2, ...)` |
| nn.ReLU() | Activation: negatives become 0 | Use between hidden layers |
| nn.Sigmoid() | Squish output to 0-1 | Use for yes/no output |
| nn.BCELoss() | Loss for binary classification | Measures prediction error |
| model(input) | Run data through the network | Returns predictions |
| loss.backward() | Calculate gradients for all layers | One line replaces manual math |
| optimizer.step() | Update all weights | Uses gradients from backward() |
| epoch | One pass through all training data | 100 epochs = 100 passes |
