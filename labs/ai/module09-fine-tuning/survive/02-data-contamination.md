# SURVIVE 02: Data Contamination

Your fine-tuned model shows 99% accuracy. Your manager is thrilled. Then you deploy it and accuracy drops to 60%. The test set leaked into training data - your metrics were fake the entire time.

---

## The Scenario

A DBA fine-tuned a BERT model for alert classification. They split the data 80/20. But they augmented the data BEFORE splitting - so augmented versions of test examples ended up in the training set. The model memorized the test set without the DBA realizing it.

---

## Step 1. See the problem

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np
from sklearn.model_selection import train_test_split

torch.manual_seed(42)
np.random.seed(42)

# Generate data
n = 200
X = np.random.uniform(0, 1, (n, 5)).astype(np.float32)
y = ((X[:, 0] > 0.5) & (X[:, 1] > 0.3)).astype(np.float32)

# ===== WRONG WAY: Augment BEFORE splitting =====
# This is the mistake - augmented copies cross the train/test boundary

def augment(X, y, noise=0.01):
    """Add tiny noise to create 'new' examples."""
    X_aug = X + np.random.normal(0, noise, X.shape).astype(np.float32)
    # noise=0.01 means almost identical copies
    return np.vstack([X, X_aug]), np.concatenate([y, y])
    # np.vstack stacks arrays vertically (more rows)
    # np.concatenate joins arrays end to end

# WRONG: augment first, then split
X_aug_all, y_aug_all = augment(X, y, noise=0.01)
X_train_bad, X_test_bad, y_train_bad, y_test_bad = train_test_split(
    X_aug_all, y_aug_all, test_size=0.2, random_state=42
)
# Problem: X_test_bad contains near-copies of examples in X_train_bad!

# ===== RIGHT WAY: Split FIRST, then augment only training =====

X_train_good, X_test_good, y_train_good, y_test_good = train_test_split(
    X, y, test_size=0.2, random_state=42
)
# Augment only training data
X_train_aug, y_train_aug = augment(X_train_good, y_train_good, noise=0.01)
# Test set stays clean - no augmented copies

# Train both models
def make_model():
    return nn.Sequential(
        nn.Linear(5, 32), nn.ReLU(),
        nn.Linear(32, 16), nn.ReLU(),
        nn.Linear(16, 1), nn.Sigmoid(),
    )

def train_and_eval(model, X_tr, y_tr, X_te, y_te, epochs=100):
    X_tr = torch.tensor(X_tr)
    y_tr = torch.tensor(y_tr).reshape(-1, 1)
    X_te = torch.tensor(X_te)
    y_te = torch.tensor(y_te).reshape(-1, 1)

    optimizer = optim.Adam(model.parameters(), lr=0.01)
    loss_fn = nn.BCELoss()

    for epoch in range(epochs):
        model.train()
        loss = loss_fn(model(X_tr), y_tr)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

    model.eval()
    with torch.no_grad():
        train_acc = ((model(X_tr) > 0.5).float() == y_tr).float().mean().item()
        test_acc = ((model(X_te) > 0.5).float() == y_te).float().mean().item()
    return train_acc, test_acc

# Train contaminated model
model_bad = make_model()
train_acc_bad, test_acc_bad = train_and_eval(
    model_bad,
    X_train_bad, y_train_bad,
    X_test_bad, y_test_bad
)

# Train clean model
model_good = make_model()
train_acc_good, test_acc_good = train_and_eval(
    model_good,
    X_train_aug.astype(np.float32), y_train_aug.astype(np.float32),
    X_test_good.astype(np.float32), y_test_good.astype(np.float32)
)

# Now test BOTH models on truly unseen data
X_new = np.random.uniform(0, 1, (100, 5)).astype(np.float32)
y_new = ((X_new[:, 0] > 0.5) & (X_new[:, 1] > 0.3)).astype(np.float32)
X_new_t = torch.tensor(X_new)
y_new_t = torch.tensor(y_new).reshape(-1, 1)

model_bad.eval()
model_good.eval()
with torch.no_grad():
    real_acc_bad = ((model_bad(X_new_t) > 0.5).float() == y_new_t).float().mean().item()
    real_acc_good = ((model_good(X_new_t) > 0.5).float() == y_new_t).float().mean().item()

print("Data Contamination - The Invisible Bug")
print("=" * 60)
print()
print(f"{'':30s}  {'Train':>7s}  {'Test':>7s}  {'Real':>7s}")
print("-" * 60)
print(f"{'WRONG: augment then split':30s}  {train_acc_bad:>6.1%}  {test_acc_bad:>6.1%}  {real_acc_bad:>6.1%}")
print(f"{'RIGHT: split then augment':30s}  {train_acc_good:>6.1%}  {test_acc_good:>6.1%}  {real_acc_good:>6.1%}")
print()
print("The contaminated model's test accuracy is INFLATED")
print("because test examples have near-copies in the training set.")
print("Real-world performance tells the truth.")
print()
print("This bug is INVISIBLE in your metrics until you deploy!")
PYEOF
```

Expected output (yours will differ):

```
Data Contamination - The Invisible Bug
============================================================

                                Train     Test     Real
------------------------------------------------------------
WRONG: augment then split        98.0%    96.0%    82.0%
RIGHT: split then augment        95.0%    88.0%    87.0%

The contaminated model's test accuracy is INFLATED
```

---

## Step 2. The contamination checklist

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Data Contamination Checklist:

1. ALWAYS split BEFORE augmentation
   WRONG: augment(data) -> split(augmented_data)
   RIGHT: split(data) -> augment(train_only)

2. ALWAYS split BEFORE normalization
   WRONG: scaler.fit_transform(all_data) -> split()
   RIGHT: split() -> scaler.fit(train) -> scaler.transform(test)
   (You learned this in Module 06 - SURVIVE 01)

3. NEVER shuffle after splitting (if using index-based split)
   WRONG: shuffle(data) -> data[:800] as train, data[800:] as test
          -> shuffle again -> data[:800] now has old test data!
   RIGHT: use train_test_split() which handles this correctly

4. CHECK for near-duplicates across train/test
   def check_contamination(X_train, X_test, threshold=0.99):
       from sklearn.metrics.pairwise import cosine_similarity
       sims = cosine_similarity(X_test, X_train)
       contaminated = (sims.max(axis=1) > threshold).sum()
       print(f"Contaminated: {contaminated}/{len(X_test)} test examples")

5. HOLD OUT a final test set that you NEVER touch during development
   - Train set: 70% (for training)
   - Validation set: 15% (for tuning hyperparameters)
   - Test set: 15% (for final evaluation ONLY)
   - The test set is like a sealed envelope - open only at the end

6. For text data specifically:
   - Check for substring matches (not just exact duplicates)
   - Paraphrased versions can leak too
   - If you augmented with synonym replacement, check that
     no augmented text matches a test text

Common contamination sources:
  - Data augmentation before split (most common)
  - Feature engineering using full dataset statistics
  - K-fold CV where augmentation happens before folding
  - Copy-paste errors when creating datasets
  - Using the same data source for train and test
""")
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Augment before split | Test accuracy inflated | Always split first, augment train only |
| Normalize before split | Test accuracy inflated | Fit scaler on train, transform test |
| Near-duplicates in train/test | Model memorizes test set | Check cosine similarity across sets |
| No held-out final test set | Can't detect the problem | Keep a sealed test set for final eval |
| Shuffle after index-based split | Train/test boundary shifts | Use train_test_split function |
