# SURVIVE 01: Catastrophic Forgetting

Your fine-tuned model classifies database alerts perfectly. But now it can't do basic text understanding - it forgot everything it learned during pre-training. The learning rate was too high and you destroyed the model's foundation.

---

## The Scenario

A DBA fine-tuned DistilBERT on 200 database alerts. Training accuracy hit 98%. But when they tested with general English sentences, the model output garbage. It lost its ability to understand language.

---

## Step 1. See the problem

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

torch.manual_seed(42)
np.random.seed(42)

# Simulate: pre-trained model that knows Task A and Task B
# Task A = "general knowledge" (large dataset)
# Task B = "your specific task" (small dataset)

# Task A data (general: can the model still do this after fine-tuning?)
n_a = 1000
X_a = np.random.uniform(0, 1, (n_a, 10)).astype(np.float32)
y_a = ((X_a[:, 0] + X_a[:, 1]) > 1.0).astype(np.float32)

# Task B data (specific: what we fine-tune on)
n_b = 100  # small dataset - common in DBA work
X_b = np.random.uniform(0, 1, (n_b, 10)).astype(np.float32)
y_b = ((X_b[:, 2] > 0.5) & (X_b[:, 3] > 0.5)).astype(np.float32)

X_a_t = torch.tensor(X_a)
y_a_t = torch.tensor(y_a).reshape(-1, 1)
X_b_t = torch.tensor(X_b)
y_b_t = torch.tensor(y_b).reshape(-1, 1)

def make_model():
    return nn.Sequential(
        nn.Linear(10, 64), nn.ReLU(),
        nn.Linear(64, 32), nn.ReLU(),
        nn.Linear(32, 1), nn.Sigmoid(),
    )

def evaluate(model, X, y):
    model.eval()
    with torch.no_grad():
        acc = ((model(X) > 0.5).float() == y).float().mean().item()
    return acc

# Step 1: Pre-train on Task A (general knowledge)
model = make_model()
optimizer = optim.Adam(model.parameters(), lr=0.01)
loss_fn = nn.BCELoss()

for epoch in range(100):
    model.train()
    pred = model(X_a_t[:800])
    loss = loss_fn(pred, y_a_t[:800])
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

pretrain_task_a_acc = evaluate(model, X_a_t[800:], y_a_t[800:])
pretrain_task_b_acc = evaluate(model, X_b_t, y_b_t)
print("After pre-training on Task A:")
print(f"  Task A accuracy: {pretrain_task_a_acc:.1%} (general knowledge)")
print(f"  Task B accuracy: {pretrain_task_b_acc:.1%} (not trained on this)")
print()

# Step 2: Fine-tune on Task B with HIGH learning rate (catastrophic forgetting)
print("Fine-tuning on Task B with HIGH learning rate (0.01)...")
print("-" * 50)

# Save pre-trained weights
pretrained_state = {k: v.clone() for k, v in model.state_dict().items()}

optimizer = optim.Adam(model.parameters(), lr=0.01)  # TOO HIGH!

for epoch in range(50):
    model.train()
    pred = model(X_b_t[:80])
    loss = loss_fn(pred, y_b_t[:80])
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

    if epoch % 10 == 0:
        task_a_acc = evaluate(model, X_a_t[800:], y_a_t[800:])
        task_b_acc = evaluate(model, X_b_t[80:], y_b_t[80:])
        print(f"  Epoch {epoch:>3d}  Task A: {task_a_acc:.1%}  Task B: {task_b_acc:.1%}")

final_a = evaluate(model, X_a_t[800:], y_a_t[800:])
final_b = evaluate(model, X_b_t[80:], y_b_t[80:])
print()
print(f"RESULT:")
print(f"  Task A went from {pretrain_task_a_acc:.1%} -> {final_a:.1%}  FORGOTTEN!")
print(f"  Task B went from {pretrain_task_b_acc:.1%} -> {final_b:.1%}")
print()
print("The model learned Task B but FORGOT Task A!")
print("This is catastrophic forgetting.")
PYEOF
```

Expected output (yours will differ):

```
After pre-training on Task A:
  Task A accuracy: 95.0% (general knowledge)
  Task B accuracy: 55.0% (not trained on this)

Fine-tuning on Task B with HIGH learning rate (0.01)...
--------------------------------------------------
  Epoch   0  Task A: 89.0%  Task B: 60.0%
  Epoch  10  Task A: 72.0%  Task B: 80.0%
  Epoch  20  Task A: 58.0%  Task B: 85.0%
  Epoch  30  Task A: 52.0%  Task B: 90.0%
  Epoch  40  Task A: 50.0%  Task B: 90.0%

RESULT:
  Task A went from 95.0% -> 50.0%  FORGOTTEN!
  Task B went from 55.0% -> 90.0%
```

---

## Step 2. The fix - small learning rate

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

torch.manual_seed(42)
np.random.seed(42)

n_a = 1000
X_a = np.random.uniform(0, 1, (n_a, 10)).astype(np.float32)
y_a = ((X_a[:, 0] + X_a[:, 1]) > 1.0).astype(np.float32)
n_b = 100
X_b = np.random.uniform(0, 1, (n_b, 10)).astype(np.float32)
y_b = ((X_b[:, 2] > 0.5) & (X_b[:, 3] > 0.5)).astype(np.float32)

X_a_t, y_a_t = torch.tensor(X_a), torch.tensor(y_a).reshape(-1, 1)
X_b_t, y_b_t = torch.tensor(X_b), torch.tensor(y_b).reshape(-1, 1)

def make_model():
    return nn.Sequential(
        nn.Linear(10, 64), nn.ReLU(),
        nn.Linear(64, 32), nn.ReLU(),
        nn.Linear(32, 1), nn.Sigmoid(),
    )

def evaluate(model, X, y):
    model.eval()
    with torch.no_grad():
        return ((model(X) > 0.5).float() == y).float().mean().item()

loss_fn = nn.BCELoss()

# Pre-train
model = make_model()
optimizer = optim.Adam(model.parameters(), lr=0.01)
for epoch in range(100):
    model.train()
    loss = loss_fn(model(X_a_t[:800]), y_a_t[:800])
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

pretrained_state = {k: v.clone() for k, v in model.state_dict().items()}
pretrain_a = evaluate(model, X_a_t[800:], y_a_t[800:])

# Compare three approaches
print("Catastrophic Forgetting - Fix Comparison")
print("=" * 65)
print(f"Pre-trained Task A accuracy: {pretrain_a:.1%}")
print()
print(f"{'Strategy':45s}  {'Task A':>7s}  {'Task B':>7s}")
print("-" * 65)

# Fix 1: Small learning rate
model1 = make_model()
model1.load_state_dict(pretrained_state)
optimizer1 = optim.Adam(model1.parameters(), lr=0.0001)  # 100x smaller!
for epoch in range(50):
    model1.train()
    loss = loss_fn(model1(X_b_t[:80]), y_b_t[:80])
    optimizer1.zero_grad()
    loss.backward()
    optimizer1.step()
a1 = evaluate(model1, X_a_t[800:], y_a_t[800:])
b1 = evaluate(model1, X_b_t[80:], y_b_t[80:])
print(f"{'Fix 1: Small lr (0.0001)':45s}  {a1:>6.1%}  {b1:>6.1%}")

# Fix 2: Freeze early layers
model2 = make_model()
model2.load_state_dict(pretrained_state)
for name, param in list(model2.named_parameters())[:2]:  # freeze first layer
    param.requires_grad = False
optimizer2 = optim.Adam(filter(lambda p: p.requires_grad, model2.parameters()), lr=0.001)
for epoch in range(50):
    model2.train()
    loss = loss_fn(model2(X_b_t[:80]), y_b_t[:80])
    optimizer2.zero_grad()
    loss.backward()
    optimizer2.step()
a2 = evaluate(model2, X_a_t[800:], y_a_t[800:])
b2 = evaluate(model2, X_b_t[80:], y_b_t[80:])
print(f"{'Fix 2: Freeze early layers':45s}  {a2:>6.1%}  {b2:>6.1%}")

# Fix 3: Early stopping (stop before forgetting)
model3 = make_model()
model3.load_state_dict(pretrained_state)
optimizer3 = optim.Adam(model3.parameters(), lr=0.001)
best_combined = 0
best_state = None
for epoch in range(50):
    model3.train()
    loss = loss_fn(model3(X_b_t[:80]), y_b_t[:80])
    optimizer3.zero_grad()
    loss.backward()
    optimizer3.step()
    a = evaluate(model3, X_a_t[800:], y_a_t[800:])
    b = evaluate(model3, X_b_t[80:], y_b_t[80:])
    combined = a + b
    if combined > best_combined:
        best_combined = combined
        best_state = {k: v.clone() for k, v in model3.state_dict().items()}
model3.load_state_dict(best_state)
a3 = evaluate(model3, X_a_t[800:], y_a_t[800:])
b3 = evaluate(model3, X_b_t[80:], y_b_t[80:])
print(f"{'Fix 3: Early stopping (monitor both tasks)':45s}  {a3:>6.1%}  {b3:>6.1%}")

# No fix - catastrophic forgetting
model_bad = make_model()
model_bad.load_state_dict(pretrained_state)
optimizer_bad = optim.Adam(model_bad.parameters(), lr=0.01)
for epoch in range(50):
    model_bad.train()
    loss = loss_fn(model_bad(X_b_t[:80]), y_b_t[:80])
    optimizer_bad.zero_grad()
    loss.backward()
    optimizer_bad.step()
a_bad = evaluate(model_bad, X_a_t[800:], y_a_t[800:])
b_bad = evaluate(model_bad, X_b_t[80:], y_b_t[80:])
print(f"{'No fix: High lr (0.01) - CATASTROPHIC':45s}  {a_bad:>6.1%}  {b_bad:>6.1%}")

print()
print("Best approach: combine small learning rate + freeze early layers")
print("The model learns Task B WITHOUT forgetting Task A")
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Learning rate too high | Model forgets pre-trained knowledge | Use lr 10x-100x smaller than pre-training |
| All layers trainable | Early layers overwritten | Freeze early layers (general knowledge) |
| Train too long | Quality degrades over time | Early stopping on validation loss |
| No baseline tracking | Don't notice forgetting | Test on general tasks AND your specific task |
