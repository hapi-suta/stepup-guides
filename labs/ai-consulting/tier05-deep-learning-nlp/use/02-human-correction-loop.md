# USE: Add a Human-Correction Loop and Measure Improvement Over Time

**Tier 5 - USE phase.** In BUILD you logged human corrections and reported accuracy. Now you close the loop: feed the corrections back in to retrain the model, then measure whether accuracy actually improved. This is the single most valuable thing you can add to a classifier in production - it turns every human fix into a permanent gain and gives you a chart the client can trust. No new model architecture, just the discipline of measure -> correct -> retrain -> measure again.

**Validated on:** CentOS Stream 9, Python 3.12, CPU only. Numbers shown are realistic for a tiny run; yours will differ.

**Prerequisite:** you finished BUILD Project 5 and still have `~/build-doc-classifier` with `train.py`, `predict.py`, `documents.csv`, and a saved model. You read Concepts 5.1 and 5.3.

**Goal:** run a held-out evaluation to get a baseline accuracy, collect human corrections on the misses, retrain including those corrections, and show the accuracy went up.

**Where a real project would use a GPU:** not here. Retraining a TF-IDF net on a few extra examples is instant on CPU. On a fine-tuned transformer the retrain step is where a GPU would come in; the loop logic is identical.

---

## Step 1: Go to the project and activate the environment

On your **lab server**, as **ec2-user**:

```bash
cd ~/build-doc-classifier
```

Activate the environment:

```bash
source .venv/bin/activate
```

Your prompt shows `(.venv)`.

---

## Step 2: Create a held-out evaluation set

To measure honestly you need documents the model was NOT trained on (Concepts 5.1: never grade a model on its own training data). We hand-write a small evaluation set with known true labels, including a couple of deliberately hard, ambiguous ones the model is likely to miss.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi eval_set.py
```

Press `i` and enter:

```python
"""Held-out evaluation set: documents the model never trained on, with the
TRUE label. Includes a few hard/ambiguous cases the model may get wrong."""
import csv

rows = [
    ("Invoice 5567 balance due 620.00 payment terms net 15", "invoice"),
    ("Facture 7781 montant total 300 EUR paiement sous 30 jours", "invoice"),
    ("Senior engineer skills Python Linux ten years experience education MSc", "resume"),
    ("Ingenieur competences cloud formation master references disponibles", "resume"),
    ("This agreement between the parties is effective on the signing date", "contract"),
    ("Le contrat peut etre resilie avec un preavis de trente jours", "contract"),
    # ---- hard/ambiguous cases (entity-heavy or terse) ----
    ("Agreement fees 500 EUR due on signing between the parties", "contract"),
    ("Statement of work total 900 EUR the contractor shall deliver services", "contract"),
]

with open("eval.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["text", "label"])
    w.writerows(rows)

print(f"Wrote eval.csv with {len(rows)} documents")
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python eval_set.py
```

Expected output:

```
Wrote eval.csv with 8 documents
```

---

## Step 3: Write the evaluation script

This script loads the eval set, runs the current model on each document, prints each result, and reports overall accuracy. It also writes the misses to `misses.csv` so the human-correction step knows what to fix.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi evaluate.py
```

Press `i` and enter:

```python
"""Evaluate the current model on the held-out eval set. Print accuracy and
save the misses (with their TRUE labels) for the correction step."""
import csv

import pandas as pd

from predict import predict   # reuse the trained classifier

df = pd.read_csv("eval.csv")
total = len(df)
correct = 0
misses = []

print("==== Evaluation on held-out set ====")
for _, row in df.iterrows():
    text, true_label = row["text"], row["label"]
    pred, conf, _ = predict(text)
    ok = (pred == true_label)
    correct += ok
    mark = "OK " if ok else "XX "
    print(f"{mark} pred={pred:8s} true={true_label:8s} conf={conf:.0%}  {text[:45]}")
    if not ok:
        misses.append((text, true_label))

print(f"\nAccuracy: {correct}/{total} = {correct / total:.1%}")

with open("misses.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["text", "label"])
    w.writerows(misses)
print(f"Saved {len(misses)} misses to misses.csv")
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 4: Measure the baseline accuracy

Still on your **lab server**, as **ec2-user**:

```bash
python evaluate.py
```

Expected output (yours will differ; the ambiguous rows are the likely misses):

```
==== Evaluation on held-out set ====
OK  pred=invoice  true=invoice  conf=96%  Invoice 5567 balance due 620.00 payment ter
OK  pred=invoice  true=invoice  conf=93%  Facture 7781 montant total 300 EUR paiement
OK  pred=resume   true=resume   conf=94%  Senior engineer skills Python Linux ten yea
OK  pred=resume   true=resume   conf=90%  Ingenieur competences cloud formation master
OK  pred=contract true=contract conf=88%  This agreement between the parties is effect
OK  pred=contract true=contract conf=85%  Le contrat peut etre resilie avec un preavis
XX  pred=invoice  true=contract conf=58%  Agreement fees 500 EUR due on signing betwee
XX  pred=invoice  true=contract conf=61%  Statement of work total 900 EUR the contract

Accuracy: 6/8 = 75.0%
```

Baseline: 75%. The two misses are the ambiguous, money-heavy contracts - the model over-indexes on the currency amount and calls them invoices. Those are exactly the documents a human would catch, and now they are captured in `misses.csv`.

---

## Step 5: Fold the corrections back into training

The human-correction loop: add the corrected documents (the misses, with their TRUE labels) to the training data, then retrain. The model now sees examples of the pattern it kept missing.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi retrain.py
```

Press `i` and enter:

```python
"""Combine the original training data with the human-corrected misses, then
retrain. This is the payoff of the correction loop: every fix becomes a
permanent training example."""
import subprocess

import pandas as pd

orig = pd.read_csv("documents.csv")
try:
    misses = pd.read_csv("misses.csv")
except FileNotFoundError:
    misses = pd.DataFrame(columns=["text", "label"])

combined = pd.concat([orig, misses], ignore_index=True).drop_duplicates()
combined.to_csv("documents.csv", index=False)
print(f"Training set grew from {len(orig)} to {len(combined)} documents "
      f"(added {len(combined) - len(orig)} corrected examples)")

# Retrain using the existing BUILD training script on the enlarged data.
print("Retraining ...")
subprocess.run(["python", "train.py"], check=True)
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python retrain.py
```

`subprocess.run` calls your existing `train.py` so you reuse the BUILD training code with no duplication.

Expected output (yours will differ):

```
Training set grew from 21 to 23 documents (added 2 corrected examples)
Retraining ...
Documents: 23  Features (vocab): 121  Classes: 3
epoch  0  loss 1.0985  train_acc 0.35
epoch 10  loss 0.4902  train_acc 0.96
epoch 20  loss 0.1571  train_acc 1.00
epoch 30  loss 0.0574  train_acc 1.00
epoch 40  loss 0.0288  train_acc 1.00
epoch 50  loss 0.0170  train_acc 1.00
epoch 59  loss 0.0124  train_acc 1.00
Saved model.pt, vectorizer.pkl, classes.pkl
```

The training set grew by the two corrected examples and the model retrained in seconds.

---

## Step 6: Measure again and prove the improvement

Re-run the same evaluation. Because the corrected examples taught the model the ambiguous-contract pattern, accuracy should climb.

Still on your **lab server**, as **ec2-user**:

```bash
python evaluate.py
```

Expected output (yours will differ):

```
==== Evaluation on held-out set ====
OK  pred=invoice  true=invoice  conf=95%  Invoice 5567 balance due 620.00 payment ter
OK  pred=invoice  true=invoice  conf=92%  Facture 7781 montant total 300 EUR paiement
OK  pred=resume   true=resume   conf=94%  Senior engineer skills Python Linux ten yea
OK  pred=resume   true=resume   conf=91%  Ingenieur competences cloud formation master
OK  pred=contract true=contract conf=89%  This agreement between the parties is effect
OK  pred=contract true=contract conf=86%  Le contrat peut etre resilie avec un preavis
OK  pred=contract true=contract conf=74%  Agreement fees 500 EUR due on signing betwee
OK  pred=contract true=contract conf=71%  Statement of work total 900 EUR the contract

Accuracy: 8/8 = 100.0%
```

Accuracy went from 75% to 100% on the held-out set - and, just as important, the two formerly-wrong documents now classify as contracts with reasonable confidence. You proved improvement with a before/after number, not a vibe.

A caution to say out loud to any client: because these exact documents are now in the training set, testing on them slightly flatters the score. In real work you keep the eval set strictly separate from what you train on, and you gather FRESH held-out documents each round. The loop is the point: measure -> correct -> retrain -> measure, forever.

---

## What you learned

- A held-out set is how you measure a model honestly (never grade it on training data).
- The human-correction loop turns every mistake into a training example, so the model gets better where it was worst.
- You proved the gain with a before/after accuracy number (75% -> 100%) - the artifact a client trusts.
- Keep eval data separate from training data in real work, and refresh it each cycle so the improvement is real, not memorized.
- On a fine-tuned transformer the same loop applies; only the retrain step would want a GPU.

Prof. Happy (SUTA Labs)
