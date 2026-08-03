# Build 03: Training Techniques

A neural network that trains is good. A neural network that trains WELL is better. This build covers the techniques that make the difference: batches, dropout, early stopping, and saving models.

---

## Step 1. Batch training - don't feed all data at once

Training on ALL data at once is slow and uses lots of memory. Batch training splits data into small chunks and updates weights after each chunk.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import TensorDataset, DataLoader
import numpy as np

np.random.seed(42)
n = 500

# Create data
cpu = np.random.uniform(0, 1, n).astype(np.float32)
memory = np.random.uniform(0, 1, n).astype(np.float32)
connections = np.random.uniform(0, 1, n).astype(np.float32)
incident = ((cpu > 0.7) & (connections > 0.7) | (memory > 0.9)).astype(np.float32)

X = torch.tensor(np.column_stack([cpu, memory, connections]))
y = torch.tensor(incident).reshape(-1, 1)

# Split
split = int(0.8 * n)
X_train, X_test = X[:split], X[split:]
y_train, y_test = y[:split], y[split:]

# --- DataLoader: feeds data in batches ---
# TensorDataset wraps X and y together
# DataLoader splits them into batches
train_dataset = TensorDataset(X_train, y_train)

# batch_size=32 means: feed 32 samples at a time
# shuffle=True means: randomize the order each epoch
train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True)

print(f"Total training samples: {len(X_train)}")
print(f"Batch size: 32")
print(f"Batches per epoch: {len(train_loader)}")
print(f"  (400 samples / 32 per batch = {400//32} full batches + 1 partial)")
print()

# Build model
model = nn.Sequential(
    nn.Linear(3, 16), nn.ReLU(),
    nn.Linear(16, 8), nn.ReLU(),
    nn.Linear(8, 1), nn.Sigmoid(),
)
loss_fn = nn.BCELoss()
optimizer = optim.Adam(model.parameters(), lr=0.01)

# --- Training with batches ---
print(f"{'Epoch':>5s}  {'Train Loss':>11s}  {'Test Acc':>9s}")
print("-" * 30)

for epoch in range(50):
    model.train()  # set model to training mode
    epoch_loss = 0.0

    # DataLoader gives us one batch at a time
    # Each batch is a tuple: (batch_X, batch_y)
    for batch_X, batch_y in train_loader:
        predictions = model(batch_X)
        loss = loss_fn(predictions, batch_y)

        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

        # .item() converts a single tensor to a Python number
        epoch_loss += loss.item()

    # Average loss across all batches
    avg_loss = epoch_loss / len(train_loader)

    # Evaluate every 10 epochs
    if epoch % 10 == 0 or epoch == 49:
        model.eval()  # set model to evaluation mode
        with torch.no_grad():
            test_pred = model(X_test)
            accuracy = ((test_pred > 0.5).float() == y_test).float().mean()
        print(f"{epoch:>5d}  {avg_loss:>11.4f}  {accuracy.item():>8.1%}")

print()
print("model.train() vs model.eval():")
print("  .train() = enable dropout, batch normalization updates")
print("  .eval()  = disable them (for evaluation/prediction)")
print("  Always switch modes appropriately!")
PYEOF
```

Expected output (yours will differ):
```
Total training samples: 400
Batch size: 32
Batches per epoch: 13
  (400 samples / 32 per batch = 12 full batches + 1 partial)

Epoch  Train Loss   Test Acc
------------------------------
    0      0.6453     73.0%
   10      0.1627     96.0%
   20      0.0853     97.0%
   30      0.0585     97.0%
   40      0.0427     97.0%
   49      0.0345     97.0%
```

---

## Step 2. Dropout - prevent overfitting

Dropout randomly turns off neurons during training. This forces the network to not rely on any single neuron, making it more robust.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

np.random.seed(42)
n = 200

# Small dataset (easy to overfit)
cpu = np.random.uniform(0, 1, n).astype(np.float32)
memory = np.random.uniform(0, 1, n).astype(np.float32)
connections = np.random.uniform(0, 1, n).astype(np.float32)
incident = ((cpu > 0.7) & (connections > 0.7) | (memory > 0.9)).astype(np.float32)

X = torch.tensor(np.column_stack([cpu, memory, connections]))
y = torch.tensor(incident).reshape(-1, 1)
split = int(0.8 * n)
X_train, X_test = X[:split], X[split:]
y_train, y_test = y[:split], y[split:]

# --- Model WITHOUT dropout ---
model_no_drop = nn.Sequential(
    nn.Linear(3, 32), nn.ReLU(),
    nn.Linear(32, 32), nn.ReLU(),
    nn.Linear(32, 1), nn.Sigmoid(),
)

# --- Model WITH dropout ---
# nn.Dropout(0.3) turns off 30% of neurons randomly each batch
# Only active during training (.train() mode)
# Disabled during evaluation (.eval() mode)
model_with_drop = nn.Sequential(
    nn.Linear(3, 32), nn.ReLU(),
    nn.Dropout(0.3),          # 30% dropout after first hidden layer
    nn.Linear(32, 32), nn.ReLU(),
    nn.Dropout(0.3),          # 30% dropout after second hidden layer
    nn.Linear(32, 1), nn.Sigmoid(),
)

def train_and_evaluate(model, name, epochs=150):
    loss_fn = nn.BCELoss()
    optimizer = optim.Adam(model.parameters(), lr=0.01)

    for epoch in range(epochs):
        model.train()
        pred = model(X_train)
        loss = loss_fn(pred, y_train)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

    # Final evaluation
    model.eval()
    with torch.no_grad():
        train_acc = ((model(X_train) > 0.5).float() == y_train).float().mean()
        test_acc = ((model(X_test) > 0.5).float() == y_test).float().mean()

    gap = (train_acc - test_acc).item()
    overfit = "OVERFIT!" if gap > 0.05 else "OK"
    print(f"  {name:20s}  Train: {train_acc.item():.1%}  Test: {test_acc.item():.1%}  Gap: {gap:.1%} {overfit}")

print("Comparing models:")
train_and_evaluate(model_no_drop, "Without dropout")
train_and_evaluate(model_with_drop, "With dropout")
print()
print("Dropout reduces the gap between train and test accuracy.")
print("A smaller gap means the model generalizes better to new data.")
print()
print("When to use dropout:")
print("  - Small datasets (easy to overfit)")
print("  - Complex models (many parameters)")
print("  - Common values: 0.2 to 0.5")
print("  - Start with 0.3 and adjust based on the train/test gap")
PYEOF
```

Expected output (yours will differ):
```
Comparing models:
  Without dropout       Train: 100.0%  Test: 92.5%  Gap: 7.5% OVERFIT!
  With dropout          Train: 97.5%   Test: 95.0%  Gap: 2.5% OK

Dropout reduces the gap between train and test accuracy.
A smaller gap means the model generalizes better to new data.
```

---

## Step 3. Early stopping - know when to stop training

Training too long leads to overfitting. Early stopping monitors performance and stops when it stops improving.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

np.random.seed(42)
n = 300
cpu = np.random.uniform(0, 1, n).astype(np.float32)
memory = np.random.uniform(0, 1, n).astype(np.float32)
connections = np.random.uniform(0, 1, n).astype(np.float32)
incident = ((cpu > 0.7) & (connections > 0.7) | (memory > 0.9)).astype(np.float32)

X = torch.tensor(np.column_stack([cpu, memory, connections]))
y = torch.tensor(incident).reshape(-1, 1)
split = int(0.8 * n)
X_train, X_test = X[:split], X[split:]
y_train, y_test = y[:split], y[split:]

model = nn.Sequential(
    nn.Linear(3, 16), nn.ReLU(),
    nn.Dropout(0.2),
    nn.Linear(16, 8), nn.ReLU(),
    nn.Linear(8, 1), nn.Sigmoid(),
)
loss_fn = nn.BCELoss()
optimizer = optim.Adam(model.parameters(), lr=0.01)

# --- Early stopping ---
# float('inf') = infinity. Any real number is smaller than infinity.
# We start with infinity so the first real loss is always "better."
# DBA analogy: like initializing a MIN search with MAX_VALUE
best_test_loss = float('inf')  # start with infinity (anything is better)
patience = 10                  # stop if no improvement for 10 epochs
patience_counter = 0
best_epoch = 0

print(f"{'Epoch':>5s}  {'Train Loss':>11s}  {'Test Loss':>10s}  {'Patience':>9s}")
print("-" * 42)

for epoch in range(200):
    # Train
    model.train()
    pred = model(X_train)
    loss = loss_fn(pred, y_train)
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

    # Evaluate
    model.eval()
    with torch.no_grad():
        test_pred = model(X_test)
        test_loss = loss_fn(test_pred, y_test).item()

    # Check if test loss improved
    if test_loss < best_test_loss:
        best_test_loss = test_loss
        best_epoch = epoch
        patience_counter = 0
        # Save the best model weights
        # state_dict() exports all model weights - like pg_dump for a model
        # .copy() makes a separate copy so the original isn't modified
        best_weights = model.state_dict().copy()
    else:
        patience_counter += 1

    if epoch % 10 == 0 or patience_counter >= patience:
        print(f"{epoch:>5d}  {loss.item():>11.4f}  {test_loss:>10.4f}  {patience - patience_counter:>5d}/{patience}")

    # Stop if patience is exhausted
    if patience_counter >= patience:
        print(f"\nEarly stopping at epoch {epoch}!")
        print(f"Best test loss was at epoch {best_epoch}: {best_test_loss:.4f}")
        break

# Restore the best weights
# load_state_dict() loads weights back in - like pg_restore
model.load_state_dict(best_weights)
model.eval()
with torch.no_grad():
    final_acc = ((model(X_test) > 0.5).float() == y_test).float().mean()
print(f"Final test accuracy (from best epoch): {final_acc.item():.1%}")
print()
print("Early stopping prevents overfitting by stopping at the sweet spot.")
print("Without it, training continues and test performance gets worse.")
PYEOF
```

Expected output (yours will differ):
```
Epoch  Train Loss   Test Loss   Patience
------------------------------------------
    0      0.6898      0.6735     10/10
   10      0.2213      0.2456     10/10
   20      0.1023      0.1548     10/10
   30      0.0612      0.1289      8/10
   40      0.0384      0.1295      2/10

Early stopping at epoch 42!
Best test loss was at epoch 28: 0.1189
Final test accuracy (from best epoch): 96.7%
```

---

## Step 4. Save and load models

Once trained, save the model so you don't have to train again.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import os

# Create a simple model
model = nn.Sequential(
    nn.Linear(3, 16), nn.ReLU(),
    nn.Linear(16, 1), nn.Sigmoid(),
)

# Simulate training (just set some weights)
# In real life, you'd train first, then save
print("Before saving:")
print(f"  First weight: {model[0].weight.data[0][:3].tolist()}")

# --- Save the model ---
save_path = "/tmp/server_health_model.pt"
# torch.save() saves the model's learned weights
# model.state_dict() returns a dictionary of all weights and biases
torch.save(model.state_dict(), save_path)
file_size = os.path.getsize(save_path)
print(f"\nModel saved to: {save_path}")
print(f"File size: {file_size:,} bytes")
print()

# --- Load the model ---
# Step 1: Create the same architecture (empty model)
loaded_model = nn.Sequential(
    nn.Linear(3, 16), nn.ReLU(),
    nn.Linear(16, 1), nn.Sigmoid(),
)

# Step 2: Load the saved weights into it
loaded_model.load_state_dict(torch.load(save_path, weights_only=True))
loaded_model.eval()  # set to evaluation mode

print("After loading:")
print(f"  First weight: {loaded_model[0].weight.data[0][:3].tolist()}")
print(f"  Weights match: {torch.equal(model[0].weight, loaded_model[0].weight)}")
print()

# --- Use the loaded model to predict ---
server = torch.tensor([0.92, 0.68, 0.95])
with torch.no_grad():
    prediction = loaded_model(server)
print(f"Prediction for [CPU=92%, Mem=68%, Conn=95%]: {prediction.item():.4f}")
print()

print("Save/load pattern:")
print("  Save:  torch.save(model.state_dict(), 'model.pt')")
print("  Load:  model.load_state_dict(torch.load('model.pt', weights_only=True))")
print("  Predict: model.eval(); model(input)")
PYEOF
```

Expected output (yours will differ):
```
Before saving:
  First weight: [0.283, -0.471, 0.157]

Model saved to: /tmp/server_health_model.pt
File size: 1,359 bytes

After loading:
  First weight: [0.283, -0.471, 0.157]
  Weights match: True

Prediction for [CPU=92%, Mem=68%, Conn=95%]: 0.5234

Save/load pattern:
  Save:  torch.save(model.state_dict(), 'model.pt')
  Load:  model.load_state_dict(torch.load('model.pt', weights_only=True))
  Predict: model.eval(); model(input)
```

---

## What You Learned

| Concept | What It Is | When to Use |
|---------|-----------|-------------|
| DataLoader | Feeds data in small batches | Always for large datasets |
| batch_size | How many samples per batch | 32 is a good default |
| shuffle=True | Randomize order each epoch | Always for training |
| Dropout | Randomly disable neurons during training | When model overfits |
| model.train() | Enable dropout and training features | During training |
| model.eval() | Disable dropout for predictions | During evaluation/prediction |
| Early stopping | Stop when test loss stops improving | Always in production |
| patience | How many epochs to wait before stopping | 5-20 is typical |
| torch.save() | Save model weights to a file | After training |
| load_state_dict() | Load saved weights | For prediction/deployment |
