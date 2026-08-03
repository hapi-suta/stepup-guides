# SURVIVE 02: Wrong Loss Function

Your neural network trains but accuracy stays at 50% (random guessing). The architecture is fine. The data is fine. The loss function is wrong.

---

## The Scenario

A junior engineer used MSELoss (regression loss) for a classification problem. The model trains, loss decreases, but accuracy never improves. Switching to BCELoss fixes it.

---

## Step 1. See the broken model

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

np.random.seed(42)
torch.manual_seed(42)

# Simple classification data
n = 500
X_np = np.random.uniform(0, 1, (n, 3)).astype(np.float32)
y_np = ((X_np[:, 0] > 0.6) & (X_np[:, 1] > 0.5)).astype(np.float32)

X = torch.tensor(X_np)
y = torch.tensor(y_np).reshape(-1, 1)

# Same model architecture for both tests
def make_model():
    return nn.Sequential(
        nn.Linear(3, 16), nn.ReLU(),
        nn.Linear(16, 8), nn.ReLU(),
        nn.Linear(8, 1), nn.Sigmoid(),
    )

# --- WRONG: MSELoss for classification ---
model_mse = make_model()
optimizer_mse = optim.Adam(model_mse.parameters(), lr=0.01)
loss_fn_mse = nn.MSELoss()  # WRONG for classification!

# --- RIGHT: BCELoss for classification ---
model_bce = make_model()
optimizer_bce = optim.Adam(model_bce.parameters(), lr=0.01)
loss_fn_bce = nn.BCELoss()  # CORRECT for classification!

print(f"{'Epoch':>5s}  {'MSE Loss':>9s} {'MSE Acc':>8s}  {'BCE Loss':>9s} {'BCE Acc':>8s}")
print("-" * 50)

for epoch in range(60):
    # Train MSE model
    model_mse.train()
    pred_mse = model_mse(X[:400])
    loss_mse = loss_fn_mse(pred_mse, y[:400])
    optimizer_mse.zero_grad()
    loss_mse.backward()
    optimizer_mse.step()

    # Train BCE model
    model_bce.train()
    pred_bce = model_bce(X[:400])
    loss_bce = loss_fn_bce(pred_bce, y[:400])
    optimizer_bce.zero_grad()
    loss_bce.backward()
    optimizer_bce.step()

    if epoch % 10 == 0 or epoch == 59:
        model_mse.eval()
        model_bce.eval()
        with torch.no_grad():
            acc_mse = ((model_mse(X[400:]) > 0.5).float() == y[400:]).float().mean()
            acc_bce = ((model_bce(X[400:]) > 0.5).float() == y[400:]).float().mean()
        print(f"{epoch:>5d}  {loss_mse.item():>9.4f} {acc_mse.item():>7.1%}  "
              f"{loss_bce.item():>9.4f} {acc_bce.item():>7.1%}")

print()
print("MSE model: loss decreases but accuracy barely improves")
print("BCE model: loss decreases AND accuracy improves")
PYEOF
```

Expected output (yours will differ):
```
Epoch  MSE Loss  MSE Acc  BCE Loss  BCE Acc
--------------------------------------------------
    0    0.2012   68.0%    0.6438   68.0%
   10    0.1256   74.0%    0.2853   91.0%
   20    0.1143   76.0%    0.1612   94.0%
   30    0.1095   77.0%    0.1045   96.0%
   40    0.1067   78.0%    0.0753   97.0%
   50    0.1048   79.0%    0.0571   98.0%
   59    0.1034   80.0%    0.0459   98.0%

MSE model: loss decreases but accuracy barely improves
BCE model: loss decreases AND accuracy improves
```

---

## Step 2. Understand why MSE fails for classification

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
Why MSELoss is wrong for classification:

MSE measures: (predicted - actual)^2

For a prediction of 0.51 when the target is 1:
  MSE = (0.51 - 1.0)^2 = 0.2401
  BCE = -log(0.51) = 0.6733

For a prediction of 0.99 when the target is 1:
  MSE = (0.99 - 1.0)^2 = 0.0001
  BCE = -log(0.99) = 0.01005

The problem: MSE treats 0.51 and 0.49 as "almost the same distance from 1"
But for classification, 0.51 = correct prediction, 0.49 = WRONG prediction!

BCE (Binary Cross-Entropy) uses logarithms which create a MUCH steeper
gradient for wrong predictions, pushing the model harder to fix mistakes.
""")

# Demonstrate the gradient difference
pred = torch.tensor([0.51], requires_grad=True)
target = torch.tensor([1.0])

# MSE gradient
loss_mse = nn.MSELoss()(pred, target)
loss_mse.backward()
grad_mse = pred.grad.item()
pred.grad.zero_()

# BCE gradient
pred2 = torch.tensor([0.51], requires_grad=True)
loss_bce = nn.BCELoss()(pred2, target)
loss_bce.backward()
grad_bce = pred2.grad.item()

print(f"Prediction: 0.51, Target: 1.0")
print(f"  MSE gradient: {grad_mse:.4f}")
print(f"  BCE gradient: {grad_bce:.4f}")
print(f"  BCE pushes {abs(grad_bce/grad_mse):.1f}x harder to correct this prediction!")
PYEOF
```

Expected output:
```
Prediction: 0.51, Target: 1.0
  MSE gradient: -0.9800
  BCE gradient: -1.9608
  BCE pushes 2.0x harder to correct this prediction!
```

---

## Step 3. Loss function cheat sheet

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Loss Function Cheat Sheet:

PROBLEM TYPE             LOSS FUNCTION           OUTPUT ACTIVATION
-------------------------------------------------------------------
Binary classification    nn.BCELoss()            nn.Sigmoid()
  (yes/no, 0/1)         or BCEWithLogitsLoss()  (no sigmoid needed)

Multi-class             nn.CrossEntropyLoss()    None
  (A/B/C, 0/1/2)       (includes softmax)       (CE applies softmax)

Regression              nn.MSELoss()             None
  (predict a number)    or nn.L1Loss()           (raw number output)

Common mistakes:
  1. MSELoss for classification       -> accuracy won't improve
  2. BCELoss without sigmoid          -> loss can be negative or NaN
  3. CrossEntropyLoss with softmax    -> double softmax (wrong results)
  4. BCELoss with integer targets     -> needs float targets

Quick rules:
  - Predicting yes/no?    -> BCELoss + Sigmoid
  - Predicting A/B/C?     -> CrossEntropyLoss (no activation needed)
  - Predicting a number?  -> MSELoss (no activation needed)
""")
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| MSELoss for classification | Loss decreases but accuracy stuck | Use BCELoss |
| BCELoss without Sigmoid | NaN loss or negative values | Add nn.Sigmoid() before BCELoss |
| CrossEntropyLoss + Softmax | Incorrect probabilities | Remove Softmax (CE includes it) |
| Wrong output dimension | Shape mismatch error | Binary: output=1, Multi-class: output=num_classes |
