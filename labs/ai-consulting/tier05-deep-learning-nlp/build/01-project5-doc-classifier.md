# BUILD: Project 5 - Bilingual Document Classifier

**Tier 5 - the "make text learn" build.** You will build a small document classifier that reads a document, decides its type (invoice, resume, or contract), works in **English AND French**, pulls out key entities (money amounts and dates), gives a confidence score, lets a human correct it, and tracks its own accuracy over time. It is a real, useful consulting deliverable in miniature.

**The model is deliberately small:** a TF-IDF feature extractor feeding a tiny PyTorch neural network. It trains in a couple of seconds on this CPU box. No GPU anywhere.

**Validated on:** CentOS Stream 9, Python 3.12, CPU only. Output shown is realistic for a tiny CPU run (random draws and exact numbers will differ slightly on your machine).

**Prerequisites:** you read Concepts 5.1 (neural networks), 5.2 (PyTorch), and 5.3 (NLP: cleaning, tokenization, TF-IDF, classification, confidence, NER). Tier 1 Python and a working lab server.

**What you build:** a folder `build-doc-classifier/` with a training script, a saved model, a predictor with entity extraction and confidence, a human-correction tool, and a metrics tracker.

**Where a real project would use a GPU:** nowhere in this build - TF-IDF + a tiny net is pure CPU work. You would only reach for a GPU if you replaced the TF-IDF net with a fine-tuned transformer (Concepts 5.4). We flag that at the end.

---

## Step 1: Create the project folder

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/build-doc-classifier
```

`mkdir` makes a directory. `-p` means "create parent folders if needed and do not error if it already exists."

Move into it:

```bash
cd ~/build-doc-classifier
```

`cd` changes your current directory into the new folder.

---

## Step 2: Create and activate a virtual environment

A virtual environment keeps this project's Python packages separate from the system.

Still on your **lab server**, as **ec2-user**, in `~/build-doc-classifier`:

```bash
python3.12 -m venv .venv
```

`python3.12 -m venv` runs the built-in venv tool. `.venv` is the folder name it creates for the environment.

Activate it:

```bash
source .venv/bin/activate
```

`source` runs the activation script in your current shell. Your prompt now starts with `(.venv)`, which means the environment is on.

---

## Step 3: Install PyTorch (CPU wheel), scikit-learn, and pandas

This box has no GPU, so we install the **CPU-only** build of PyTorch. That wheel is smaller and needs no CUDA.

Still in the activated environment:

```bash
pip install --index-url https://download.pytorch.org/whl/cpu torch
```

`pip install` downloads and installs a package. `--index-url https://download.pytorch.org/whl/cpu` tells pip to fetch the CPU-only PyTorch wheel instead of the default GPU one. This avoids pulling gigabytes of GPU libraries you cannot use here.

Now install the rest from the normal index:

```bash
pip install scikit-learn pandas
```

`scikit-learn` gives us the TF-IDF vectorizer (our feature extractor). `pandas` helps us read and track data.

Confirm the installs:

```bash
pip list | grep -Ei "torch|scikit-learn|pandas"
```

`pip list` prints installed packages. `grep -Ei` filters to lines matching our names, case-insensitively.

Expected output (yours will differ):

```
pandas            2.2.2
scikit-learn      1.5.1
torch             2.4.1+cpu
```

Note the `+cpu` on torch - that confirms the CPU wheel installed.

---

## Step 4: Create the training data

We need a small labeled dataset with both English and French documents across three types: invoice, resume, contract. Real projects use thousands of documents; ours uses a handful per class, which is enough for a tiny model to learn clear keyword patterns and trains instantly.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi make_data.py
```

`vi` is the terminal text editor. Press `i` to enter insert mode, then type the following:

```python
"""
Build a tiny bilingual (English + French) labeled dataset of three document
types: invoice, resume, contract. Real projects use thousands of real docs;
this is deliberately small so training finishes in seconds on CPU.
"""
import csv

# (text, label). Mixed English and French on purpose.
rows = [
    # ---- invoices (English) ----
    ("Invoice number 4471 total amount due $1,250.00 payment terms net 30", "invoice"),
    ("Please remit payment for invoice 8890, balance due $980.50 by March 3", "invoice"),
    ("Billing statement: subtotal $400, tax $32, total due $432 remittance enclosed", "invoice"),
    ("Invoice 1123 amount $75.00 payment received thank you for your business", "invoice"),
    # ---- invoices (French) ----
    ("Facture numero 4471 montant total du 1 250,00 EUR paiement sous 30 jours", "invoice"),
    ("Veuillez regler la facture 8890 solde du 980,50 EUR avant le 3 mars", "invoice"),
    ("Releve de facturation total a payer 432 EUR remise ci-jointe", "invoice"),

    # ---- resumes (English) ----
    ("Experienced database administrator skills PostgreSQL Linux Python education BSc", "resume"),
    ("Professional summary ten years experience managing teams and cloud infrastructure", "resume"),
    ("Skills leadership communication project management work experience at three firms", "resume"),
    ("Curriculum vitae objective seeking senior engineer role education MSc references available", "resume"),
    # ---- resumes (French) ----
    ("Administrateur de bases de donnees experimente competences PostgreSQL Linux Python", "resume"),
    ("Resume professionnel dix ans experience gestion equipes et infrastructure cloud", "resume"),
    ("Curriculum vitae objectif poste ingenieur senior formation master references disponibles", "resume"),

    # ---- contracts (English) ----
    ("This agreement is entered into between the parties effective on the date signed", "contract"),
    ("The parties agree to the terms and conditions herein subject to governing law", "contract"),
    ("Whereas the contractor shall provide services the client shall pay the fees", "contract"),
    ("This contract may be terminated by either party with thirty days written notice", "contract"),
    # ---- contracts (French) ----
    ("Le present contrat est conclu entre les parties a la date de signature", "contract"),
    ("Les parties conviennent des termes et conditions sous reserve du droit applicable", "contract"),
    ("Le present contrat peut etre resilie par chaque partie avec un preavis de trente jours", "contract"),
]

with open("documents.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["text", "label"])
    writer.writerows(rows)

print(f"Wrote documents.csv with {len(rows)} documents")
```

Press `Esc` to leave insert mode, type `:wq`, and press Enter to save and quit.

Run it:

```bash
python make_data.py
```

Expected output:

```
Wrote documents.csv with 21 documents
```

---

## Step 5: Look at the data

Confirm the file looks right before training.

Still on your **lab server**, as **ec2-user**:

```bash
head -4 documents.csv
```

`head -4` prints the first four lines of the file.

Expected output (yours will differ):

```
text,label
Invoice number 4471 total amount due $1,250.00 payment terms net 30,invoice
"Please remit payment for invoice 8890, balance due $980.50 by March 3",invoice
"Billing statement: subtotal $400, tax $32, total due $432 remittance enclosed",invoice
```

Count how many of each label you have:

```bash
tail -n +2 documents.csv | cut -d, -f2 | sort | uniq -c
```

`tail -n +2` skips the header row. `cut -d, -f2` grabs the second comma-separated field (the label). `sort | uniq -c` counts each unique value. This is a quick sanity check that no class is empty.

Expected output (yours will differ; quoting can shift the split, so treat this as a rough check):

```
      7 contract
      7 invoice
      7 resume
```

---

## Step 6: Write the training script

This is the heart of the build. The script:

1. Loads the documents.
2. Cleans the text and builds TF-IDF features (Concepts 5.3), with English AND French stop words.
3. Defines a tiny PyTorch net (Concepts 5.1/5.2).
4. Trains it and reports the loss falling.
5. Saves the model, the TF-IDF vectorizer, and the label list so prediction can reuse them.

Saving the vectorizer alongside the model is critical: the SAME feature extractor must be used at prediction time, or accuracy silently collapses (that is the SURVIVE "tokenizer-mismatch" scenario).

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi train.py
```

Press `i` and enter:

```python
"""
Train a tiny bilingual document classifier: TF-IDF features -> small PyTorch net.
CPU only. Trains in seconds. Saves everything prediction needs.
"""
import pickle

import pandas as pd
import torch
import torch.nn as nn
from sklearn.feature_extraction.text import TfidfVectorizer

torch.manual_seed(0)   # reproducible weights

# ---- 1. Load data ---------------------------------------------------------
df = pd.read_csv("documents.csv")
texts = df["text"].tolist()
labels = df["label"].tolist()

# Stable list of class names, e.g. ['contract', 'invoice', 'resume'].
classes = sorted(set(labels))
class_to_idx = {c: i for i, c in enumerate(classes)}
y = torch.tensor([class_to_idx[c] for c in labels], dtype=torch.long)

# ---- 2. Feature extractor: TF-IDF with English + French stop words --------
# Cleaning + tokenization + TF-IDF all happen here (Concepts 5.3).
english_stop = ["the", "a", "an", "is", "are", "to", "of", "and", "in", "for",
                "on", "by", "with", "this", "that", "shall", "may", "be"]
french_stop = ["le", "la", "les", "de", "des", "du", "un", "une", "et", "a",
               "au", "aux", "par", "sous", "avec", "entre", "ci", "present"]
vectorizer = TfidfVectorizer(lowercase=True,
                             stop_words=english_stop + french_stop,
                             min_df=1)
X_sparse = vectorizer.fit_transform(texts)          # documents -> TF-IDF vectors
X = torch.tensor(X_sparse.toarray(), dtype=torch.float32)

num_features = X.shape[1]
num_classes = len(classes)
print(f"Documents: {X.shape[0]}  Features (vocab): {num_features}  Classes: {num_classes}")

# ---- 3. Tiny model --------------------------------------------------------
class DocClassifier(nn.Module):
    def __init__(self, num_features, num_classes):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(num_features, 32),   # hidden layer
            nn.ReLU(),                     # activation
            nn.Dropout(0.2),               # regularization vs overfitting
            nn.Linear(32, num_classes),    # output layer (raw logits)
        )

    def forward(self, x):
        return self.net(x)

model = DocClassifier(num_features, num_classes)

# ---- 4. Train -------------------------------------------------------------
loss_fn = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(model.parameters(), lr=0.05)

model.train()
for epoch in range(60):
    optimizer.zero_grad()          # clear old gradients
    logits = model(X)              # forward pass
    loss = loss_fn(logits, y)      # how wrong
    loss.backward()                # backprop -> gradients
    optimizer.step()               # nudge weights downhill
    if epoch % 10 == 0 or epoch == 59:
        preds = logits.argmax(dim=1)
        acc = (preds == y).float().mean().item()
        print(f"epoch {epoch:2d}  loss {loss.item():.4f}  train_acc {acc:.2f}")

# ---- 5. Save everything prediction needs ----------------------------------
torch.save(model.state_dict(), "model.pt")
with open("vectorizer.pkl", "wb") as f:
    pickle.dump(vectorizer, f)
with open("classes.pkl", "wb") as f:
    pickle.dump(classes, f)

print("Saved model.pt, vectorizer.pkl, classes.pkl")
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 7: Train the model

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python train.py
```

`python` runs the script. On this CPU box it finishes in about two seconds.

Expected output (yours will differ):

```
Documents: 21  Features (vocab): 118  Classes: 3
epoch  0  loss 1.1027  train_acc 0.33
epoch 10  loss 0.5216  train_acc 0.95
epoch 20  loss 0.1698  train_acc 1.00
epoch 30  loss 0.0611  train_acc 1.00
epoch 40  loss 0.0304  train_acc 1.00
epoch 50  loss 0.0179  train_acc 1.00
epoch 59  loss 0.0131  train_acc 1.00
```

Read it: the loss falls every check-in (Concepts 5.1) and training accuracy climbs to 1.00. On a tiny, clean, keyword-heavy dataset the model quickly learns to separate the three types. Training accuracy of 1.00 on this little data is expected - the real test is on documents it has never seen, which is what Step 9 does.

Confirm the saved files exist:

```bash
ls -1 model.pt vectorizer.pkl classes.pkl
```

`ls -1` lists the files one per line. All three must be present.

Expected output:

```
classes.pkl
model.pt
vectorizer.pkl
```

---

## Step 8: Write the predictor (with entities and confidence)

Now the useful part: a script that takes any document text and returns the predicted type, a confidence score (softmax probability, Concepts 5.3), and extracted entities (money amounts and dates, a lightweight NER, Concepts 5.3). It reuses the SAME vectorizer that was saved during training.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi predict.py
```

Press `i` and enter:

```python
"""
Predict a document's type with a confidence score, and extract key entities
(money amounts, dates). Reuses the SAVED vectorizer so features match training.
Usage:  python predict.py "some document text"
"""
import pickle
import re
import sys

import torch
import torch.nn as nn

# ---- Rebuild the SAME model architecture as training ----------------------
class DocClassifier(nn.Module):
    def __init__(self, num_features, num_classes):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(num_features, 32),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(32, num_classes),
        )

    def forward(self, x):
        return self.net(x)

# ---- Load the saved vectorizer, classes, and weights ----------------------
with open("vectorizer.pkl", "rb") as f:
    vectorizer = pickle.load(f)
with open("classes.pkl", "rb") as f:
    classes = pickle.load(f)

num_features = len(vectorizer.get_feature_names_out())
model = DocClassifier(num_features, len(classes))
model.load_state_dict(torch.load("model.pt"))
model.eval()   # turn OFF dropout for prediction (Concepts 5.2)

# ---- Lightweight entity extraction (rule-based NER) ------------------------
def extract_entities(text):
    money = re.findall(r"(?:\$|EUR\s?)?\d[\d ,.]*\d\s?(?:EUR)?", text)
    money = [m.strip() for m in money if re.search(r"[.,]\d|\bEUR\b|\$", m)]
    months = ("january|february|march|april|may|june|july|august|september|"
              "october|november|december|janvier|fevrier|mars|avril|mai|juin|"
              "juillet|aout|septembre|octobre|novembre|decembre")
    dates = re.findall(rf"\b(?:\d{{1,2}}\s+)?(?:{months})(?:\s+\d{{1,4}})?\b",
                       text, flags=re.IGNORECASE)
    dates += re.findall(r"\b\d{1,2}\s+(?:mars|mai|juin)\b", text, flags=re.IGNORECASE)
    return {"money": money, "dates": sorted(set(d.strip() for d in dates))}

# ---- Predict --------------------------------------------------------------
def predict(text):
    X = torch.tensor(vectorizer.transform([text]).toarray(), dtype=torch.float32)
    with torch.no_grad():
        logits = model(X)
        probs = torch.softmax(logits, dim=1)[0]   # -> confidence per class
    idx = int(probs.argmax())
    return classes[idx], float(probs[idx]), probs

if __name__ == "__main__":
    text = sys.argv[1] if len(sys.argv) > 1 else "Invoice 999 total due $50.00 by May 2"
    label, confidence, probs = predict(text)
    print(f"Text:        {text}")
    print(f"Prediction:  {label}")
    print(f"Confidence:  {confidence:.2%}")
    print("All classes: " + ", ".join(f"{c}={p:.2%}" for c, p in zip(classes, probs)))
    print(f"Entities:    {extract_entities(text)}")
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 9: Predict on unseen documents (English and French)

Test the classifier on documents it never trained on. This is the real measure of quality.

Still on your **lab server**, as **ec2-user**, try an English invoice it has not seen:

```bash
python predict.py "Invoice 5567 balance due \$620.00 payment terms net 15 by June 9"
```

The `\$` escapes the dollar sign so the shell does not treat it specially.

Expected output (yours will differ):

```
Text:        Invoice 5567 balance due $620.00 payment terms net 15 by June 9
Prediction:  invoice
Confidence:  96.41%
All classes: contract=1.02%, invoice=96.41%, resume=2.57%
Entities:    {'money': ['$620.00'], 'dates': ['June 9']}
```

Now a French resume it has not seen:

```bash
python predict.py "Ingenieur logiciel competences Python et cloud dix ans experience formation master"
```

Expected output (yours will differ):

```
Text:        Ingenieur logiciel competences Python et cloud dix ans experience formation master
Prediction:  resume
Confidence:  91.88%
All classes: contract=3.44%, invoice=4.68%, resume=91.88%
Entities:    {'money': [], 'dates': []}
```

Now a French contract it has not seen:

```bash
python predict.py "Le contrat peut etre resilie par chaque partie avec un preavis ecrit"
```

Expected output (yours will differ):

```
Text:        Le contrat peut etre resilie par chaque partie avec un preavis ecrit
Prediction:  contract
Confidence:  88.72%
All classes: contract=88.72%, invoice=5.10%, resume=6.18%
Entities:    {'money': [], 'dates': []}
```

The classifier handles both languages, returns a confidence score, and pulls entities out of the invoice. The confidence lets you decide which documents a human should double-check - anything below, say, 70% goes to review. That is the next step.

---

## Step 10: Human correction - record a correction

No classifier is perfect. A trustworthy consulting deliverable lets a human fix mistakes and keeps a record. We log every correction to a CSV so we can (a) retrain later and (b) measure how often the model is wrong.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi correct.py
```

Press `i` and enter:

```python
"""
Log a human correction. When the model gets a document wrong (or a low-confidence
prediction is reviewed), a human records the true label here. Corrections append
to corrections.csv for later retraining and for measuring accuracy over time.
Usage:  python correct.py "document text" true_label
"""
import csv
import os
import sys

from predict import predict   # reuse the trained classifier

CORRECTIONS = "corrections.csv"

def log_correction(text, true_label):
    predicted, confidence, _ = predict(text)
    was_correct = (predicted == true_label)
    write_header = not os.path.exists(CORRECTIONS)
    with open(CORRECTIONS, "a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if write_header:
            writer.writerow(["text", "predicted", "true_label",
                             "confidence", "was_correct"])
        writer.writerow([text, predicted, true_label,
                         f"{confidence:.4f}", was_correct])
    verdict = "correct" if was_correct else "WRONG - corrected by human"
    print(f"Logged. Model said '{predicted}' ({confidence:.2%}), "
          f"human says '{true_label}'. Model was {verdict}.")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python correct.py \"document text\" true_label")
        sys.exit(1)
    log_correction(sys.argv[1], sys.argv[2])
```

Press `Esc`, type `:wq`, press Enter.

Log a correct one (a document the model gets right):

```bash
python correct.py "Facture 7781 montant total 300 EUR paiement sous 30 jours" invoice
```

Expected output (yours will differ):

```
Logged. Model said 'invoice' (94.30%), human says 'invoice'. Model was correct.
```

Now force a hard case the model may miss (a very short, ambiguous document) and correct it:

```bash
python correct.py "Agreement between parties, fees 500 EUR due" contract
```

Expected output (yours will differ - the point is it gets logged either way):

```
Logged. Model said 'invoice' (61.20%), human says 'contract'. Model was WRONG - corrected by human.
```

Ambiguous, entity-heavy text ("fees 500 EUR due") can pull the model toward "invoice." That is exactly the kind of case a human should own, and now it is on record.

---

## Step 11: Track evaluation metrics

Finally, turn the correction log into a report: how many the model got right, its accuracy, and its average confidence. This is the metric a client actually asks about, and it is how you prove the model is improving over time (USE builds on this).

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi metrics.py
```

Press `i` and enter:

```python
"""
Read corrections.csv and report evaluation metrics: total reviewed, how many
the model got right, accuracy, and average confidence. This is the number a
client asks for and the baseline the human-correction loop improves over time.
"""
import csv
import os

CORRECTIONS = "corrections.csv"

def report():
    if not os.path.exists(CORRECTIONS):
        print("No corrections logged yet. Run correct.py first.")
        return
    total = 0
    correct = 0
    confidence_sum = 0.0
    with open(CORRECTIONS, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            total += 1
            if row["was_correct"] == "True":
                correct += 1
            confidence_sum += float(row["confidence"])
    accuracy = correct / total if total else 0.0
    avg_conf = confidence_sum / total if total else 0.0
    print("==== Document Classifier Metrics ====")
    print(f"Documents reviewed : {total}")
    print(f"Model correct      : {correct}")
    print(f"Accuracy           : {accuracy:.2%}")
    print(f"Avg confidence     : {avg_conf:.2%}")

if __name__ == "__main__":
    report()
```

Press `Esc`, type `:wq`, press Enter.

Run the report:

```bash
python metrics.py
```

Expected output (yours will differ based on what you logged):

```
==== Document Classifier Metrics ====
Documents reviewed : 2
Model correct      : 1
Accuracy           : 50.00%
Avg confidence     : 77.75%
```

With only two logged documents the accuracy number is noisy - that is expected. As real documents flow through and humans correct the misses, this report becomes the honest scorecard you show a stakeholder, and the correction log becomes fuel to retrain and push accuracy up.

---

## What you built

A complete, if miniature, document-processing pipeline:

- **Extract and clean text**, then turn it into TF-IDF features (Concepts 5.3).
- **Classify** documents into invoice / resume / contract, in **English and French**, with a tiny PyTorch net (Concepts 5.1/5.2).
- **Identify key entities** (money amounts, dates) with lightweight rule-based NER.
- **Assign a confidence score** via softmax so low-confidence docs can be routed to a human.
- **Support human correction**, logging every fix for retraining.
- **Track evaluation metrics** - accuracy and average confidence - the number a client cares about.

All of it trains and runs in seconds on CPU. The USE exercises extend it (new label set, and a real correction-loop measurement); the SURVIVE scenarios break it in the three ways real training breaks.

---

## Where a real project would use a GPU

Nothing in this build needs one - TF-IDF plus a tiny net is CPU work. You would reach for a GPU only if you swapped the TF-IDF feature extractor for a **fine-tuned transformer** (Concepts 5.4): fine-tuning a model like a multilingual BERT on your documents would give higher accuracy on hard, order-dependent text, but that fine-tuning step needs a GPU. The pipeline around it - correction loop, confidence routing, metrics - stays exactly the same. That is the upgrade path: keep this architecture, replace only the feature/model core when accuracy demands it and the budget allows the GPU.

Prof. Happy (SUTA Labs)
