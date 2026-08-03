# USE: Swap the Classifier Head to a New Label Set

**Tier 5 - USE phase.** In BUILD you trained a three-class document classifier (invoice / resume / contract). A client now asks for something different: sort those same documents by **sentiment** - positive, neutral, negative (Concepts 5.3). You do NOT need to rebuild everything. You reuse the expensive part - the TF-IDF feature extractor - and only train a new **head** (the final output layer) for the new labels. This is exactly the "reuse the body, swap the head" pattern behind transfer learning and fine-tuning (Concepts 5.4), done here in miniature on CPU.

**Validated on:** CentOS Stream 9, Python 3.12, CPU only. Numbers shown are realistic for a tiny run; yours will differ.

**Prerequisite:** you finished BUILD Project 5 and still have `~/build-doc-classifier` with `vectorizer.pkl` in it. You read Concepts 5.1 (layers, output layer), 5.2 (PyTorch), 5.3 (sentiment analysis).

**Goal:** keep the trained TF-IDF vectorizer, attach a fresh 3-class sentiment head, train only that head, and classify sentiment - without retraining the feature extractor.

**Where a real project would use a GPU:** not here. Freezing a feature extractor and training only a small head is fast CPU work. On a real transformer you would freeze the pretrained body and train a new head the same way; that body is where a GPU would help.

---

## Step 1: Go to the project and activate the environment

On your **lab server**, as **ec2-user**:

```bash
cd ~/build-doc-classifier
```

`cd` moves you into the BUILD project folder, which already holds `vectorizer.pkl`.

Activate the environment:

```bash
source .venv/bin/activate
```

Your prompt shows `(.venv)`.

Confirm the saved vectorizer from BUILD is here - that is the part we are reusing:

```bash
ls -1 vectorizer.pkl
```

Expected output:

```
vectorizer.pkl
```

---

## Step 2: Create a small sentiment dataset

We need documents labeled by sentiment instead of type. Keep it tiny and bilingual.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi sentiment_data.py
```

Press `i` and enter:

```python
"""Tiny bilingual sentiment dataset: positive, neutral, negative."""
import csv

rows = [
    ("Excellent service fast delivery very happy with the product", "positive"),
    ("Great experience the team was helpful and professional", "positive"),
    ("Service excellent livraison rapide tres satisfait du produit", "positive"),
    ("Produit fantastique je recommande vivement bravo", "positive"),

    ("The order arrived on the scheduled date as described", "neutral"),
    ("Payment was processed the account balance was updated", "neutral"),
    ("La commande est arrivee a la date prevue comme indique", "neutral"),
    ("Le paiement a ete traite le solde du compte a ete mis a jour", "neutral"),

    ("Terrible support never again the product broke immediately", "negative"),
    ("Very disappointed slow delivery and the item was damaged", "negative"),
    ("Support horrible plus jamais le produit est casse tout de suite", "negative"),
    ("Tres decu livraison lente et article endommage", "negative"),
]

with open("sentiment.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["text", "label"])
    w.writerows(rows)

print(f"Wrote sentiment.csv with {len(rows)} documents")
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python sentiment_data.py
```

Expected output:

```
Wrote sentiment.csv with 12 documents
```

---

## Step 3: Write the head-swap training script

The key idea: we call `vectorizer.transform(...)` (NOT `fit_transform`) so we reuse the EXACT vocabulary the BUILD learned. Then we build a fresh network with the same number of input features but a new output size (3 sentiment classes) and train only that.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi swap_head.py
```

Press `i` and enter:

```python
"""
Reuse the BUILD's TF-IDF vectorizer (the frozen feature extractor) and train a
fresh classification head for a NEW label set (sentiment). We do not refit the
vectorizer, so the feature extractor is untouched - only the head is trained.
"""
import pickle

import pandas as pd
import torch
import torch.nn as nn

torch.manual_seed(0)

# ---- Reuse the SAVED feature extractor (do NOT refit it) ------------------
with open("vectorizer.pkl", "rb") as f:
    vectorizer = pickle.load(f)     # trained during BUILD

df = pd.read_csv("sentiment.csv")
# transform (not fit_transform): reuse the existing vocabulary unchanged.
X = torch.tensor(vectorizer.transform(df["text"]).toarray(), dtype=torch.float32)

classes = sorted(set(df["label"]))
class_to_idx = {c: i for i, c in enumerate(classes)}
y = torch.tensor([class_to_idx[c] for c in df["label"]], dtype=torch.long)

num_features = X.shape[1]
print(f"Reusing frozen vectorizer with {num_features} features")
print(f"New label set: {classes}")

# ---- A fresh head for the NEW labels --------------------------------------
# Same input width as BUILD (features are identical), new output width.
head = nn.Sequential(
    nn.Linear(num_features, 16),
    nn.ReLU(),
    nn.Linear(16, len(classes)),
)

loss_fn = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(head.parameters(), lr=0.05)

head.train()
for epoch in range(60):
    optimizer.zero_grad()
    logits = head(X)
    loss = loss_fn(logits, y)
    loss.backward()
    optimizer.step()
    if epoch % 15 == 0 or epoch == 59:
        acc = (logits.argmax(1) == y).float().mean().item()
        print(f"epoch {epoch:2d}  loss {loss.item():.4f}  train_acc {acc:.2f}")

torch.save(head.state_dict(), "sentiment_head.pt")
with open("sentiment_classes.pkl", "wb") as f:
    pickle.dump(classes, f)
print("Saved sentiment_head.pt and sentiment_classes.pkl")
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 4: Train the new head

Still on your **lab server**, as **ec2-user**:

```bash
python swap_head.py
```

Expected output (yours will differ):

```
Reusing frozen vectorizer with 118 features
New label set: ['negative', 'neutral', 'positive']
epoch  0  loss 1.0994  train_acc 0.33
epoch 15  loss 0.3145  train_acc 1.00
epoch 30  loss 0.0987  train_acc 1.00
epoch 45  loss 0.0421  train_acc 1.00
epoch 59  loss 0.0257  train_acc 1.00
```

Notice you never touched the vectorizer - it kept the 118-feature vocabulary from BUILD - yet you trained a completely different classifier in seconds. That is the point: the reusable feature extractor did the heavy lifting, and swapping the head cost almost nothing.

---

## Step 5: Predict sentiment on unseen text

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi predict_sentiment.py
```

Press `i` and enter:

```python
"""Predict sentiment using the reused vectorizer + the new sentiment head."""
import pickle
import sys

import torch
import torch.nn as nn

with open("vectorizer.pkl", "rb") as f:
    vectorizer = pickle.load(f)
with open("sentiment_classes.pkl", "rb") as f:
    classes = pickle.load(f)

num_features = len(vectorizer.get_feature_names_out())
head = nn.Sequential(
    nn.Linear(num_features, 16),
    nn.ReLU(),
    nn.Linear(16, len(classes)),
)
head.load_state_dict(torch.load("sentiment_head.pt"))
head.eval()

text = sys.argv[1] if len(sys.argv) > 1 else "the product broke immediately terrible"
X = torch.tensor(vectorizer.transform([text]).toarray(), dtype=torch.float32)
with torch.no_grad():
    probs = torch.softmax(head(X), dim=1)[0]
idx = int(probs.argmax())
print(f"Text:       {text}")
print(f"Sentiment:  {classes[idx]}  ({probs[idx]:.2%})")
```

Press `Esc`, type `:wq`, press Enter.

Try a negative English review it never saw:

```bash
python predict_sentiment.py "very disappointed the item was damaged and support was terrible"
```

Expected output (yours will differ):

```
Text:       very disappointed the item was damaged and support was terrible
Sentiment:  negative  (93.10%)
```

Try a positive French review:

```bash
python predict_sentiment.py "produit fantastique tres satisfait je recommande"
```

Expected output (yours will differ):

```
Text:       produit fantastique tres satisfait je recommande
Sentiment:  positive  (90.44%)
```

---

## What you learned

- The feature extractor (TF-IDF vectorizer) is reusable across tasks. You froze it and trained only a new head.
- Swapping the head to a new label set (document type -> sentiment) took seconds and no retraining of the expensive part.
- This is transfer learning in miniature. On a real transformer (Concepts 5.4) the pattern is identical: freeze the pretrained body, train a new head - the body is the part that would need a GPU to build, and reusing it is exactly why fine-tuning is so much cheaper than pretraining.

Prof. Happy (SUTA Labs)
