# Build 03: LoRA - Efficient Fine-Tuning

LoRA (Low-Rank Adaptation) is the most practical fine-tuning technique in production. Instead of updating millions of model parameters, LoRA adds tiny trainable matrices alongside the frozen model. You get 90%+ of full fine-tuning quality at a fraction of the cost.

---

## Step 1. Understand what LoRA does

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
LoRA: Low-Rank Adaptation

The Problem:
  BERT has 110M parameters. Full fine-tuning updates ALL of them.
  For GPT-3 (175B parameters), full fine-tuning is nearly impossible.
  Even freezing and training just the head limits what you can learn.

The LoRA Solution:
  Keep the original model COMPLETELY frozen.
  Add two tiny matrices (A and B) next to each layer.
  Only train A and B (typically < 1% of original parameters).

How it works for a weight matrix W (e.g., 768 x 768):
  Original: output = input @ W           (W is frozen)
  With LoRA: output = input @ W + input @ A @ B

  W shape: [768, 768] = 589,824 params (FROZEN)
  A shape: [768, 4]   = 3,072 params   (trainable)
  B shape: [4, 768]   = 3,072 params   (trainable)
  LoRA adds only 6,144 params vs 589,824 original

  The "4" is called the "rank" (r). Lower rank = fewer params.
  r=4 is typical. r=8 for harder tasks. r=16 for complex tasks.

DBA analogy:
  Original model = your production database (don't touch it)
  LoRA = a materialized view with computed columns
  You don't modify the base tables, you add a lightweight layer
  that provides the specific functionality you need.
""")
PYEOF
```

---

## Step 2. Build LoRA from scratch

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

torch.manual_seed(42)

class LoRALayer(nn.Module):
    """A single LoRA adapter for one linear layer."""

    def __init__(self, original_layer, rank=4, alpha=1.0):
        super().__init__()
        # original_layer: the frozen nn.Linear layer from the pre-trained model
        # rank: how many dimensions for the low-rank matrices (smaller = fewer params)
        # alpha: scaling factor for the LoRA output

        self.original = original_layer
        self.rank = rank
        self.alpha = alpha

        in_features = original_layer.in_features   # input dimension
        out_features = original_layer.out_features  # output dimension

        # Freeze the original layer
        for param in self.original.parameters():
            param.requires_grad = False

        # LoRA matrices: A (down-project) and B (up-project)
        self.A = nn.Linear(in_features, rank, bias=False)
        # A projects from full dimension DOWN to rank
        # Shape: [in_features, rank] e.g., [768, 4]
        self.B = nn.Linear(rank, out_features, bias=False)
        # B projects from rank back UP to full dimension
        # Shape: [rank, out_features] e.g., [4, 768]

        # Initialize A with random values, B with zeros
        # This means LoRA starts with zero contribution (no change to original)
        nn.init.kaiming_normal_(self.A.weight)
        # Kaiming initialization: good starting values for training
        nn.init.zeros_(self.B.weight)
        # Zero init: LoRA output = 0 at start, so model = original

    def forward(self, x):
        # Original output (frozen, no gradient)
        original_output = self.original(x)

        # LoRA output (trainable)
        lora_output = self.B(self.A(x))
        # x -> A (down-project to rank) -> B (up-project to full dim)

        # Scale and combine
        return original_output + (self.alpha / self.rank) * lora_output
        # alpha/rank scales the LoRA contribution
        # Larger alpha = LoRA has more influence

# Demo: add LoRA to a linear layer
original = nn.Linear(768, 768)  # simulates one BERT layer
original_params = sum(p.numel() for p in original.parameters())

lora = LoRALayer(original, rank=4)
lora_trainable = sum(p.numel() for p in lora.parameters() if p.requires_grad)
lora_total = sum(p.numel() for p in lora.parameters())

print("LoRA Layer Analysis:")
print(f"  Original layer:    {original_params:>10,} params (frozen)")
print(f"  LoRA A matrix:     {768 * 4:>10,} params (trainable)")
print(f"  LoRA B matrix:     {4 * 768:>10,} params (trainable)")
print(f"  Total trainable:   {lora_trainable:>10,} params")
print(f"  Ratio:             {lora_trainable/lora_total*100:.2f}% of total")
print()

# Test forward pass
x = torch.randn(2, 768)  # 2 examples, 768-dim (like BERT)
output = lora(x)
print(f"Input shape:  {x.shape}")
print(f"Output shape: {output.shape}")
print()

# Compare different ranks
print("Effect of rank on parameter count:")
print(f"  {'Rank':>4s}  {'LoRA Params':>12s}  {'% of Original':>14s}")
print(f"  {'-'*4}  {'-'*12}  {'-'*14}")
for r in [1, 2, 4, 8, 16, 32]:
    params = 768 * r + r * 768  # A + B
    pct = params / original_params * 100
    print(f"  {r:>4d}  {params:>12,}  {pct:>13.2f}%")
PYEOF
```

Expected output (yours will differ):

```
LoRA Layer Analysis:
  Original layer:       590,592 params (frozen)
  LoRA A matrix:          3,072 params (trainable)
  LoRA B matrix:          3,072 params (trainable)
  Total trainable:        6,144 params
  Ratio:                  1.03% of total

Effect of rank on parameter count:
  Rank  LoRA Params  % of Original
  ----  ------------ ---------------
     1         1,536           0.26%
     2         3,072           0.52%
     4         6,144           1.04%
     8        12,288           2.08%
    16        24,576           4.16%
    32        49,152           8.32%
```

---

## Step 3. Apply LoRA to a model

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np

torch.manual_seed(42)
np.random.seed(42)

class LoRALayer(nn.Module):
    def __init__(self, original_layer, rank=4, alpha=1.0):
        super().__init__()
        self.original = original_layer
        for param in self.original.parameters():
            param.requires_grad = False
        in_f = original_layer.in_features
        out_f = original_layer.out_features
        self.A = nn.Linear(in_f, rank, bias=False)
        self.B = nn.Linear(rank, out_f, bias=False)
        nn.init.kaiming_normal_(self.A.weight)
        nn.init.zeros_(self.B.weight)
        self.scale = alpha / rank

    def forward(self, x):
        return self.original(x) + self.scale * self.B(self.A(x))

def add_lora_to_model(model, rank=4):
    """Replace all Linear layers with LoRA-wrapped versions."""
    for name, module in model.named_children():
        # named_children() gives direct child modules
        if isinstance(module, nn.Linear):
            # isinstance checks if module is a Linear layer
            lora_layer = LoRALayer(module, rank=rank)
            setattr(model, name, lora_layer)
            # setattr replaces the module in the model
        elif isinstance(module, nn.Sequential):
            # For Sequential containers, recurse into them
            for i, layer in enumerate(module):
                if isinstance(layer, nn.Linear):
                    module[i] = LoRALayer(layer, rank=rank)
    return model

# Create a "pre-trained" model
class PretrainedModel(nn.Module):
    def __init__(self):
        super().__init__()
        self.layers = nn.Sequential(
            nn.Linear(10, 64), nn.ReLU(),
            nn.Linear(64, 64), nn.ReLU(),
            nn.Linear(64, 32), nn.ReLU(),
            nn.Linear(32, 4),  # 4-class classification
        )
    def forward(self, x):
        return self.layers(x)

# Generate classification data
n = 500
X = np.random.uniform(0, 1, (n, 10)).astype(np.float32)
# 4-class rule based on feature combinations
y = np.zeros(n, dtype=np.int64)
y[(X[:, 0] > 0.5) & (X[:, 1] > 0.5)] = 1
y[(X[:, 2] > 0.5) & (X[:, 3] > 0.5)] = 2
y[(X[:, 0] > 0.7) & (X[:, 2] > 0.7)] = 3

X_train = torch.tensor(X[:400])
y_train = torch.tensor(y[:400])
X_test = torch.tensor(X[400:])
y_test = torch.tensor(y[400:])

# Pre-train the model
model = PretrainedModel()
optimizer = optim.Adam(model.parameters(), lr=0.01)
loss_fn = nn.CrossEntropyLoss()

for epoch in range(100):
    logits = model(X_train)
    loss = loss_fn(logits, y_train)
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

model.eval()
with torch.no_grad():
    pretrain_acc = (model(X_test).argmax(dim=-1) == y_test).float().mean().item()
print(f"Pre-trained accuracy: {pretrain_acc:.1%}")

# Now add LoRA and fine-tune
print()
print("Adding LoRA adapters...")
model = add_lora_to_model(model, rank=4)

total = sum(p.numel() for p in model.parameters())
trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
print(f"Total parameters:     {total:>8,}")
print(f"Trainable (LoRA):     {trainable:>8,} ({trainable/total*100:.1f}%)")
print()

# Fine-tune with LoRA
optimizer = optim.Adam(
    filter(lambda p: p.requires_grad, model.parameters()),
    lr=0.001
)

print(f"{'Epoch':>5s}  {'Loss':>8s}  {'Accuracy':>9s}")
print("-" * 28)

for epoch in range(50):
    model.train()
    logits = model(X_train)
    loss = loss_fn(logits, y_train)
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

    if epoch % 10 == 0 or epoch == 49:
        model.eval()
        with torch.no_grad():
            acc = (model(X_test).argmax(dim=-1) == y_test).float().mean().item()
        print(f"{epoch:>5d}  {loss.item():>8.4f}  {acc:>8.1%}")

print()
print(f"Pre-trained accuracy:  {pretrain_acc:.1%}")
print(f"After LoRA fine-tune:  {acc:.1%}")
print(f"Only trained {trainable:,} parameters out of {total:,}")
PYEOF
```

Expected output (yours will differ):

```
Pre-trained accuracy: 82.0%

Adding LoRA adapters...
Total parameters:      7,484
Trainable (LoRA):      1,720 (23.0%)

Epoch     Loss  Accuracy
----------------------------
    0    0.6234     84.0%
   10    0.3456     89.0%
   ...
   49    0.1234     93.0%

Pre-trained accuracy:  82.0%
After LoRA fine-tune:  93.0%
Only trained 1,720 parameters out of 7,484
```

---

## Step 4. LoRA in practice with PEFT

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
In practice, you don't build LoRA from scratch.
Use the PEFT library (Parameter-Efficient Fine-Tuning) from HuggingFace.

Installation:
  pip3 install peft

Usage (pseudocode - requires GPU for large models):

  from transformers import AutoModelForSequenceClassification
  from peft import get_peft_model, LoraConfig

  # Load pre-trained model
  model = AutoModelForSequenceClassification.from_pretrained(
      "distilbert-base-uncased",
      num_labels=4
  )

  # Add LoRA
  lora_config = LoraConfig(
      r=8,              # rank (4-16 typical)
      lora_alpha=16,    # scaling factor
      target_modules=["q_lin", "v_lin"],  # which layers to adapt
      lora_dropout=0.1, # dropout for LoRA layers
  )

  model = get_peft_model(model, lora_config)
  model.print_trainable_parameters()
  # Output: trainable params: 147,456 || all params: 66,955,010 || trainable%: 0.22%

  # Train normally - only LoRA params update
  # Save only LoRA weights (tiny file):
  model.save_pretrained("my_lora_adapter")
  # This saves just the LoRA weights (~1MB vs 250MB for full model)

  # Load: original model + tiny LoRA adapter
  model = AutoModelForSequenceClassification.from_pretrained("distilbert-base-uncased")
  model = PeftModel.from_pretrained(model, "my_lora_adapter")

Key benefits:
  1. Train 0.1-1% of parameters (fast, low memory)
  2. Save tiny adapter files (~1MB each)
  3. Can have MULTIPLE adapters for different tasks on the same base model
  4. No catastrophic forgetting (base model is completely frozen)

When to use LoRA:
  - Limited GPU memory
  - Need to experiment with different fine-tuning configurations
  - Want multiple specialized models from one base model
  - Production deployment with multiple tasks

LoRA vs Full Fine-Tuning:
  - LoRA: 90-95% of full fine-tuning quality, 100x fewer trainable params
  - Full: Best quality, but expensive and risks catastrophic forgetting
  - For most tasks, LoRA is the better choice
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | Why It Matters |
|---------|-------------|---------------|
| LoRA matrices (A, B) | Small trainable adapters next to frozen layers | 100x fewer parameters than full fine-tuning |
| Rank (r) | Controls adapter size (4-16 typical) | Lower = fewer params, higher = more capacity |
| Alpha | Scales LoRA's contribution | Controls how much LoRA changes the output |
| Zero initialization of B | LoRA starts with zero contribution | Model starts identical to pre-trained |
| PEFT library | Production-ready LoRA implementation | Don't build from scratch in production |
| Multiple adapters | Different LoRA for different tasks | One base model, many specializations |
