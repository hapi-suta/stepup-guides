# Build 04: Practical Neural Network

Everything from Builds 01-03 combined into one real project. You'll build, train, evaluate, and save a neural network that predicts server incidents - using proper techniques.

---

## Step 1. The complete pipeline

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import TensorDataset, DataLoader
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report

# ============================
# STEP 1: Prepare Data
# ============================
np.random.seed(42)
n = 1000

# 6 features (realistic server metrics)
cpu = np.random.uniform(5, 99, n)
memory = np.random.uniform(10, 99, n)
connections = np.random.uniform(1, 300, n)
disk = np.random.uniform(10, 99, n)
wal_growth = np.random.uniform(0, 50, n)
replication_lag = np.random.uniform(0, 120, n)

# Incident rule (complex - linear models would struggle with this)
incident = (
    ((cpu > 80) & (connections > 200)) |
    ((memory > 85) & (disk > 80)) |
    ((wal_growth > 35) & (replication_lag > 60)) |
    ((cpu > 90) & (memory > 80) & (connections > 150))
).astype(np.float32)

# Add 5% noise
noise = np.random.random(n) < 0.05
incident[noise] = 1 - incident[noise]

# Combine into arrays
X_raw = np.column_stack([cpu, memory, connections, disk, wal_growth, replication_lag])
y_raw = incident

feature_names = ['cpu', 'memory', 'connections', 'disk', 'wal_growth', 'repl_lag']

print(f"Dataset: {n} servers, {len(feature_names)} features")
print(f"Incidents: {int(incident.sum())} ({incident.mean()*100:.1f}%)")
print()

# ============================
# STEP 2: Split and Normalize
# ============================
# Split FIRST (no data leakage)
X_train_raw, X_test_raw, y_train_raw, y_test_raw = train_test_split(
    X_raw, y_raw, test_size=0.2, random_state=42, stratify=y_raw
)
# stratify=y_raw keeps the same incident ratio in train and test

# Normalize: fit on train, transform both
scaler = StandardScaler()
X_train_np = scaler.fit_transform(X_train_raw).astype(np.float32)
X_test_np = scaler.transform(X_test_raw).astype(np.float32)

# Convert to PyTorch tensors
X_train = torch.tensor(X_train_np)
X_test = torch.tensor(X_test_np)
y_train = torch.tensor(y_train_raw).reshape(-1, 1)
y_test = torch.tensor(y_test_raw).reshape(-1, 1)

# Create DataLoader for batched training
train_loader = DataLoader(
    TensorDataset(X_train, y_train),
    batch_size=32, shuffle=True
)

print(f"Train: {len(X_train)} samples")
print(f"Test:  {len(X_test)} samples")
print()

# ============================
# STEP 3: Build Model
# ============================
model = nn.Sequential(
    nn.Linear(6, 32),    # 6 inputs -> 32 hidden
    nn.ReLU(),
    nn.Dropout(0.2),     # prevent overfitting
    nn.Linear(32, 16),   # 32 -> 16 hidden
    nn.ReLU(),
    nn.Dropout(0.2),
    nn.Linear(16, 1),    # 16 -> 1 output
    nn.Sigmoid(),        # probability output
)

total_params = sum(p.numel() for p in model.parameters())
print(f"Model: {total_params} parameters")
print(model)
print()

# ============================
# STEP 4: Train with Early Stopping
# ============================
loss_fn = nn.BCELoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)

best_test_loss = float('inf')
patience = 15
patience_counter = 0
best_weights = None

print(f"{'Epoch':>5s}  {'Loss':>8s}  {'Test Loss':>10s}  {'Test Acc':>9s}")
print("-" * 38)

for epoch in range(200):
    # Training
    model.train()
    epoch_loss = 0
    for batch_X, batch_y in train_loader:
        pred = model(batch_X)
        loss = loss_fn(pred, batch_y)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        epoch_loss += loss.item()
    avg_loss = epoch_loss / len(train_loader)

    # Evaluation
    model.eval()
    with torch.no_grad():
        test_pred = model(X_test)
        test_loss = loss_fn(test_pred, y_test).item()
        test_acc = ((test_pred > 0.5).float() == y_test).float().mean().item()

    # Early stopping
    if test_loss < best_test_loss:
        best_test_loss = test_loss
        patience_counter = 0
        best_weights = {k: v.clone() for k, v in model.state_dict().items()}
    else:
        patience_counter += 1

    if epoch % 20 == 0:
        print(f"{epoch:>5d}  {avg_loss:>8.4f}  {test_loss:>10.4f}  {test_acc:>8.1%}")

    if patience_counter >= patience:
        print(f"{epoch:>5d}  {avg_loss:>8.4f}  {test_loss:>10.4f}  {test_acc:>8.1%}  STOPPED")
        break

# Restore best weights
model.load_state_dict(best_weights)

# ============================
# STEP 5: Final Evaluation
# ============================
print()
print("=" * 50)
print("FINAL EVALUATION")
print("=" * 50)

model.eval()
with torch.no_grad():
    test_pred = model(X_test)
    test_labels = (test_pred > 0.5).float()

# Convert to numpy for sklearn metrics
y_pred_np = test_labels.numpy().flatten().astype(int)
y_true_np = y_test.numpy().flatten().astype(int)

print(classification_report(y_true_np, y_pred_np,
                           target_names=['Healthy', 'Incident']))

# ============================
# STEP 6: Save for Production
# ============================
save_path = "/tmp/incident_predictor.pt"
torch.save({
    'model_state': model.state_dict(),
    'scaler_mean': scaler.mean_,
    'scaler_scale': scaler.scale_,
    'feature_names': feature_names,
}, save_path)

print(f"Model saved to {save_path}")
print(f"Includes: model weights + scaler parameters + feature names")
print()

# ============================
# STEP 7: Load and Predict
# ============================
# Simulate loading in a new script
checkpoint = torch.load(save_path, weights_only=False)

loaded_model = nn.Sequential(
    nn.Linear(6, 32), nn.ReLU(), nn.Dropout(0.2),
    nn.Linear(32, 16), nn.ReLU(), nn.Dropout(0.2),
    nn.Linear(16, 1), nn.Sigmoid(),
)
loaded_model.load_state_dict(checkpoint['model_state'])
loaded_model.eval()

# Predict for a new server
new_server_raw = np.array([[88.0, 75.0, 220.0, 45.0, 10.0, 30.0]])  # raw metrics
new_server_scaled = (new_server_raw - checkpoint['scaler_mean']) / checkpoint['scaler_scale']
new_server_tensor = torch.tensor(new_server_scaled.astype(np.float32))

with torch.no_grad():
    prob = loaded_model(new_server_tensor).item()

print(f"\nNew server prediction:")
print(f"  CPU=88%, Mem=75%, Conn=220, Disk=45%, WAL=10MB, Lag=30s")
print(f"  Incident probability: {prob:.1%}")
print(f"  Verdict: {'INCIDENT LIKELY' if prob > 0.5 else 'Healthy'}")
PYEOF
```

Expected output (yours will differ):
```
Dataset: 1000 servers, 6 features
Incidents: 168 (16.8%)

Train: 800 samples
Test:  200 samples

Model: 737 parameters
Sequential(...)

Epoch     Loss   Test Loss   Test Acc
--------------------------------------
    0    0.5832      0.5102     78.5%
   20    0.1542      0.1823     94.5%
   40    0.0934      0.1352     96.0%
   60    0.0685      0.1268     96.0%
...STOPPED

==================================================
FINAL EVALUATION
==================================================
              precision    recall  f1-score   support

     Healthy       0.97      0.98      0.97       166
    Incident       0.91      0.88      0.90        34

    accuracy                           0.96       200

Model saved to /tmp/incident_predictor.pt
...

New server prediction:
  CPU=88%, Mem=75%, Conn=220, Disk=45%, WAL=10MB, Lag=30s
  Incident probability: 87.3%
  Verdict: INCIDENT LIKELY
```

---

## What You Learned

| Step | What | Why |
|------|------|-----|
| 1. Prepare data | Generate/load, check distribution | Can't train without data |
| 2. Split + normalize | train_test_split, StandardScaler | Prevent leakage, equal feature scales |
| 3. Build model | nn.Sequential with ReLU + Dropout | Architecture defines what the model CAN learn |
| 4. Train + early stop | Batch training, patience-based stopping | Learn well, don't overfit |
| 5. Evaluate | classification_report | Know precision, recall, F1 |
| 6. Save | torch.save with scaler params | Reproducible production deployment |
| 7. Load + predict | torch.load, model.eval() | Use the model on new data |
