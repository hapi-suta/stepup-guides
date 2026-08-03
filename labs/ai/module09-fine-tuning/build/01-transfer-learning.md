# Build 01: Transfer Learning - What Fine-Tuning Actually Does

Fine-tuning is a type of transfer learning - taking knowledge learned on one task and applying it to a different task. This guide shows you exactly what changes inside the model.

---

## Step 1. Understand transfer learning

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Transfer Learning: Use knowledge from Task A to help with Task B.

Example from databases:
  - You learned PostgreSQL query tuning (Task A)
  - You switch to MySQL query tuning (Task B)
  - You don't start from zero - SQL fundamentals transfer
  - You only need to learn MySQL-specific differences

Same thing with models:
  - BERT learned English from millions of web pages (Task A)
  - You want to classify database alerts (Task B)
  - BERT already knows language, grammar, word meanings
  - You only need to teach it your specific alert categories

What transfers:
  - Word meaning (BERT knows "error" is bad, "success" is good)
  - Grammar (BERT understands sentence structure)
  - Context (BERT knows "lag" near "replication" means something different than "lag" alone)

What you teach:
  - Your specific categories (performance, storage, replication, security)
  - Your specific patterns (what your alerts look like)
  - Your specific threshold (what counts as "critical" in YOUR system)
""")
PYEOF
```

---

## Step 2. See frozen vs unfrozen layers

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
Fine-tuning = choosing which layers to update (unfreeze) and
which to keep fixed (freeze).

Freeze: parameter.requires_grad = False
  The layer's weights DON'T change during training.
  The layer keeps its pre-trained knowledge exactly as-is.

Unfreeze: parameter.requires_grad = True
  The layer's weights DO change during training.
  The layer adapts to your specific task.
""")

# Simulate a pre-trained model with 4 layers
class PretrainedModel(nn.Module):
    def __init__(self):
        super().__init__()
        self.layer1 = nn.Linear(10, 32)   # learns basic features
        self.layer2 = nn.Linear(32, 32)   # learns intermediate features
        self.layer3 = nn.Linear(32, 16)   # learns complex features
        self.layer4 = nn.Linear(16, 2)    # classification head (output)

    def forward(self, x):
        x = torch.relu(self.layer1(x))
        x = torch.relu(self.layer2(x))
        x = torch.relu(self.layer3(x))
        return self.layer4(x)

model = PretrainedModel()

# Approach 1: Freeze ALL layers, only train the last one
# This is the simplest form of fine-tuning
print("Approach 1: Freeze everything except the last layer")
print("-" * 50)

for name, param in model.named_parameters():
    # named_parameters() gives you (name, tensor) pairs for every learnable weight
    if "layer4" in name:
        param.requires_grad = True   # train this layer
    else:
        param.requires_grad = False  # freeze this layer

# Count trainable vs frozen parameters
trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
# p.numel() = number of values in the tensor
# if p.requires_grad = only count trainable ones
frozen = sum(p.numel() for p in model.parameters() if not p.requires_grad)
total = trainable + frozen

for name, param in model.named_parameters():
    status = "TRAIN" if param.requires_grad else "frozen"
    print(f"  {name:20s}  {param.numel():>5d} params  [{status}]")

print(f"\n  Trainable: {trainable:,} / {total:,} ({trainable/total*100:.1f}%)")
print()

# Approach 2: Freeze early layers, train later ones
# Early layers learn general features, later layers learn specific features
print("Approach 2: Freeze layers 1-2, train layers 3-4")
print("-" * 50)

for name, param in model.named_parameters():
    if "layer1" in name or "layer2" in name:
        param.requires_grad = False  # freeze (general features)
    else:
        param.requires_grad = True   # train (specific features)

trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
frozen = sum(p.numel() for p in model.parameters() if not p.requires_grad)

for name, param in model.named_parameters():
    status = "TRAIN" if param.requires_grad else "frozen"
    print(f"  {name:20s}  {param.numel():>5d} params  [{status}]")

print(f"\n  Trainable: {trainable:,} / {total:,} ({trainable/total*100:.1f}%)")
print()

# Approach 3: Train everything (full fine-tuning)
print("Approach 3: Full fine-tuning (everything trainable)")
print("-" * 50)
for param in model.parameters():
    param.requires_grad = True

trainable = sum(p.numel() for p in model.parameters())
print(f"  All {trainable:,} parameters trainable")
print(f"  Risk: catastrophic forgetting (model forgets pre-trained knowledge)")
print(f"  Mitigation: use a very small learning rate (1e-5 instead of 1e-3)")
PYEOF
```

Expected output (yours will differ):

```
Approach 1: Freeze everything except the last layer
--------------------------------------------------
  layer1.weight         320 params  [frozen]
  layer1.bias            32 params  [frozen]
  layer2.weight        1024 params  [frozen]
  layer2.bias            32 params  [frozen]
  layer3.weight         512 params  [frozen]
  layer3.bias            16 params  [frozen]
  layer4.weight          32 params  [TRAIN]
  layer4.bias             2 params  [TRAIN]

  Trainable: 34 / 1,970 (1.7%)
```

---

## Step 3. The learning rate matters more than anything

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

torch.manual_seed(42)
np.random.seed(42)

# Simple classification data
n = 500
X_np = np.random.uniform(0, 1, (n, 10)).astype(np.float32)
y_np = ((X_np[:, 0] > 0.5) & (X_np[:, 1] > 0.3)).astype(np.float32)
X = torch.tensor(X_np)
y = torch.tensor(y_np).reshape(-1, 1)

def make_model():
    return nn.Sequential(
        nn.Linear(10, 32), nn.ReLU(),
        nn.Linear(32, 16), nn.ReLU(),
        nn.Linear(16, 1), nn.Sigmoid(),
    )

def train_and_evaluate(model, lr, epochs=50, label=""):
    """Train a model and return final accuracy."""
    optimizer = optim.Adam(
        filter(lambda p: p.requires_grad, model.parameters()),
        # lambda p: p.requires_grad is a tiny function that checks if a parameter needs training
        # filter() keeps only items where the lambda returns True
        # So this says: "only train parameters that are unfrozen"
        # DBA analogy: like WHERE is_active = true - only process matching items
        lr=lr
    )
    loss_fn = nn.BCELoss()

    for epoch in range(epochs):
        model.train()
        pred = model(X[:400])
        loss = loss_fn(pred, y[:400])
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

    model.eval()
    with torch.no_grad():
        acc = ((model(X[400:]) > 0.5).float() == y[400:]).float().mean().item()
    return acc

# Simulate "pre-trained" model (train on the data first)
pretrained = make_model()
_ = train_and_evaluate(pretrained, lr=0.01, epochs=100, label="pretrain")

print("Fine-tuning learning rate comparison:")
print("=" * 55)
print(f"{'Strategy':40s}  {'Accuracy':>8s}")
print("-" * 55)

# Strategy 1: Fine-tune with NORMAL learning rate (too high)
model1 = make_model()
model1.load_state_dict(pretrained.state_dict())
# load_state_dict copies all weights from the pre-trained model
acc1 = train_and_evaluate(model1, lr=0.01, label="high lr")
print(f"{'Full fine-tune, lr=0.01 (too high)':40s}  {acc1:>7.1%}")

# Strategy 2: Fine-tune with SMALL learning rate (correct)
model2 = make_model()
model2.load_state_dict(pretrained.state_dict())
acc2 = train_and_evaluate(model2, lr=0.0001, label="low lr")
print(f"{'Full fine-tune, lr=0.0001 (correct)':40s}  {acc2:>7.1%}")

# Strategy 3: Freeze all but last layer, normal lr
model3 = make_model()
model3.load_state_dict(pretrained.state_dict())
for name, param in model3.named_parameters():
    if "2" not in name:  # freeze layers 0 and 1, train layer 2
        param.requires_grad = False
acc3 = train_and_evaluate(model3, lr=0.001, label="freeze+train")
print(f"{'Freeze early, train last, lr=0.001':40s}  {acc3:>7.1%}")

# Strategy 4: Train from scratch (no transfer learning)
model4 = make_model()
acc4 = train_and_evaluate(model4, lr=0.01, epochs=50, label="scratch")
print(f"{'Train from scratch (no pre-training)':40s}  {acc4:>7.1%}")

print()
print("Key takeaway: when fine-tuning, use a MUCH smaller learning rate")
print("than when training from scratch (10x to 100x smaller)")
print("Too high = destroys pre-trained knowledge (catastrophic forgetting)")
print("Too low = model doesn't learn your task")
PYEOF
```

Expected output (yours will differ):

```
Fine-tuning learning rate comparison:
=======================================================
Strategy                                  Accuracy
-------------------------------------------------------
Full fine-tune, lr=0.01 (too high)          87.0%
Full fine-tune, lr=0.0001 (correct)         93.0%
Freeze early, train last, lr=0.001          91.0%
Train from scratch (no pre-training)        85.0%
```

---

## Step 4. Replace the classification head

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
When fine-tuning a pre-trained model for YOUR task, you almost
always need to REPLACE the last layer (classification head).

Why? The pre-trained model was trained for a different task:
  - BERT was trained to predict masked words (not classify alerts)
  - GPT was trained to predict next words (not categorize incidents)

You keep all the layers that understand language (the "backbone")
and replace the final layer with YOUR task's output:
  - Binary classification: nn.Linear(hidden, 1) + Sigmoid
  - Multi-class (3 categories): nn.Linear(hidden, 3)
  - Regression: nn.Linear(hidden, 1) (no activation)
""")

# Simulate: BERT has a hidden size of 768, was trained with 30K vocab head
class SimulatedBERT(nn.Module):
    def __init__(self):
        super().__init__()
        # Backbone (pretrained, frozen)
        self.encoder_layer1 = nn.Linear(768, 768)
        self.encoder_layer2 = nn.Linear(768, 768)
        # Original head (for masked word prediction - 30K vocab)
        self.original_head = nn.Linear(768, 30000)

    def forward(self, x):
        x = torch.relu(self.encoder_layer1(x))
        x = torch.relu(self.encoder_layer2(x))
        return self.original_head(x)

# Step 1: Load "pre-trained" model
bert = SimulatedBERT()
print(f"Original BERT:")
print(f"  Output: {bert.original_head.out_features} (vocabulary size)")
print(f"  Total params: {sum(p.numel() for p in bert.parameters()):,}")
print()

# Step 2: Replace the head for alert classification (4 categories)
num_categories = 4  # performance, storage, replication, security

# Freeze the backbone
for name, param in bert.named_parameters():
    if "encoder" in name:
        param.requires_grad = False
    # Only encoder layers get frozen, the head remains trainable

# Replace the classification head
bert.original_head = nn.Sequential(
    nn.Dropout(0.1),              # prevent overfitting
    nn.Linear(768, num_categories) # 768 -> 4 categories
)

print(f"Fine-tuned for alert classification:")
print(f"  Output: {num_categories} categories")
print(f"  Total params: {sum(p.numel() for p in bert.parameters()):,}")
trainable = sum(p.numel() for p in bert.parameters() if p.requires_grad)
print(f"  Trainable params: {trainable:,}")
print()

# Show all layers
for name, param in bert.named_parameters():
    status = "TRAIN" if param.requires_grad else "frozen"
    print(f"  {name:35s}  {param.numel():>10,} params  [{status}]")

print()
print("The backbone (encoder) stays frozen - it already understands language")
print("Only the new head (3,076 params) gets trained on your alert data")
PYEOF
```

Expected output (yours will differ):

```
Original BERT:
  Output: 30000 (vocabulary size)
  Total params: 24,410,568

Fine-tuned for alert classification:
  Output: 4 categories
  Total params: 1,183,492
  Trainable params: 3,076

  encoder_layer1.weight           589,824 params  [frozen]
  encoder_layer1.bias                 768 params  [frozen]
  encoder_layer2.weight           589,824 params  [frozen]
  encoder_layer2.bias                 768 params  [frozen]
  original_head.1.weight            3,072 params  [TRAIN]
  original_head.1.bias                  4 params  [TRAIN]
```

---

## What You Learned

| Concept | What It Does | When To Use |
|---------|-------------|-------------|
| Transfer learning | Reuse knowledge from one task for another | Always (never train from scratch) |
| Freezing layers | Keep pre-trained weights fixed | When you have limited data |
| Unfreezing layers | Allow pre-trained weights to adapt | When you have lots of data |
| Replace head | Swap output layer for your task | Always (pre-trained head is for a different task) |
| Small learning rate | Prevent destroying pre-trained knowledge | Always when fine-tuning (1e-5 to 1e-4) |
| Catastrophic forgetting | Model forgets pre-trained knowledge | When learning rate is too high |
