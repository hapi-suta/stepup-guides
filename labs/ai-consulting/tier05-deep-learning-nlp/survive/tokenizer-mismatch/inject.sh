#!/usr/bin/env bash
#
# SURVIVE: tokenizer-mismatch
# The nastiest kind of NLP bug: NOTHING crashes. Training works, the model saves,
# prediction runs and returns confident answers - but the answers are wrong,
# because prediction builds a BRAND-NEW tokenizer/vectorizer instead of reusing
# the one training learned. Train and inference see different feature spaces, so
# accuracy silently collapses. Your job (runbook.md) is to catch it and fix it by
# reusing the SAVED vectorizer at prediction time.
#
# Run this on your lab server as ec2-user. It builds the working dir, a venv,
# installs CPU-only torch + scikit-learn, writes train.py and predict.py (with
# the mismatch bug), trains, and runs a self-check that reports low accuracy.
#
set -euo pipefail

WORKDIR="${HOME}/survive-tokenizer-mismatch"
VENV="${WORKDIR}/venv"

echo "==> Creating working directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Creating Python virtual environment (python3.12)"
if [[ ! -d "${VENV}" ]]; then
  python3.12 -m venv "${VENV}"
fi

# shellcheck disable=SC1091
source "${VENV}/bin/activate"

echo "==> Upgrading pip and installing CPU-only torch + scikit-learn"
python -m pip install --quiet --upgrade pip
python -m pip install --quiet --index-url https://download.pytorch.org/whl/cpu torch
python -m pip install --quiet scikit-learn

echo "==> Writing data.py (shared training data)"
cat > "${WORKDIR}/data.py" <<'PYEOF'
"""Shared tiny bilingual dataset for train.py and check.py."""
TRAIN = [
    ("invoice total amount due payment net thirty", 0),
    ("invoice balance remit payment remittance enclosed", 0),
    ("facture montant paiement solde du", 0),
    ("resume skills experience education engineer", 1),
    ("curriculum vitae objective senior role references", 1),
    ("competences experience formation ingenieur", 1),
    ("agreement parties terms conditions governing law", 2),
    ("contract terminated party written notice", 2),
    ("contrat parties termes conditions droit", 2),
]
# Held-out documents with known labels for the accuracy self-check.
TEST = [
    ("invoice amount due payment remittance enclosed", 0),
    ("facture paiement solde montant", 0),
    ("resume skills senior engineer references", 1),
    ("competences formation ingenieur experience", 1),
    ("agreement parties terms notice governing", 2),
    ("contrat termes conditions parties droit", 2),
]
LABELS = ["invoice", "resume", "contract"]
PYEOF

echo "==> Writing train.py (trains and saves model + vectorizer)"
cat > "${WORKDIR}/train.py" <<'PYEOF'
#!/usr/bin/env python3
"""Train the classifier and SAVE both the model and the fitted vectorizer."""
import pickle

import torch
import torch.nn as nn
from sklearn.feature_extraction.text import TfidfVectorizer

from data import TRAIN

torch.manual_seed(0)

texts = [t for t, _ in TRAIN]
labels = [y for _, y in TRAIN]

vectorizer = TfidfVectorizer()
X = torch.tensor(vectorizer.fit_transform(texts).toarray(), dtype=torch.float32)
y = torch.tensor(labels, dtype=torch.long)

model = nn.Sequential(nn.Linear(X.shape[1], 16), nn.ReLU(), nn.Linear(16, 3))
loss_fn = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(model.parameters(), lr=0.05)

model.train()
for epoch in range(80):
    optimizer.zero_grad()
    loss = loss_fn(model(X), y)
    loss.backward()
    optimizer.step()

torch.save(model.state_dict(), "model.pt")
# The fitted vectorizer IS saved. The bug is that check.py ignores it.
with open("vectorizer.pkl", "wb") as f:
    pickle.dump(vectorizer, f)
print(f"Trained. Final loss {loss.item():.4f}. Saved model.pt and vectorizer.pkl")
print(f"Training vocabulary size: {len(vectorizer.get_feature_names_out())}")
PYEOF

echo "==> Writing check.py (accuracy self-check WITH the tokenizer-mismatch bug)"
cat > "${WORKDIR}/check.py" <<'PYEOF'
#!/usr/bin/env python3
"""
Load the trained model and measure accuracy on held-out documents.

BUG (this is the SURVIVE scenario): instead of loading the SAVED vectorizer that
train.py fitted, this script builds a BRAND-NEW TfidfVectorizer and fits it on
the TEST texts. That new vectorizer has a different vocabulary and different
column order, so the feature vector fed to the model does not line up with what
the model learned. Nothing crashes - but the predictions are garbage and
accuracy collapses. Your job (runbook.md) is to reuse the saved vectorizer.
"""
import torch
import torch.nn as nn
from sklearn.feature_extraction.text import TfidfVectorizer

from data import TEST, LABELS

texts = [t for t, _ in TEST]
true = [y for _, y in TEST]

# BUG: brand-new vectorizer fit on the test texts, NOT the saved training one.
wrong_vectorizer = TfidfVectorizer()
Xbad = wrong_vectorizer.fit_transform(texts).toarray()
num_features_at_infer = Xbad.shape[1]

# The model was built for the TRAINING vocab width. To even run, we have to pad
# or truncate - which is itself a red flag that the feature spaces differ.
# Rebuild the model at its trained width by peeking at the saved weights.
state = torch.load("model.pt")
trained_features = state["0.weight"].shape[1]
model = nn.Sequential(nn.Linear(trained_features, 16), nn.ReLU(), nn.Linear(16, 3))
model.load_state_dict(state)
model.eval()

import numpy as np
# Force the mismatched features into the trained width (pad/truncate). This is
# exactly the kind of silent hack that hides a tokenizer mismatch in real code.
if num_features_at_infer < trained_features:
    Xbad = np.pad(Xbad, ((0, 0), (0, trained_features - num_features_at_infer)))
else:
    Xbad = Xbad[:, :trained_features]

with torch.no_grad():
    preds = model(torch.tensor(Xbad, dtype=torch.float32)).argmax(1).tolist()

correct = sum(p == t for p, t in zip(preds, true))
acc = correct / len(true)
for (text, _), p, t in zip(TEST, preds, true):
    mark = "OK " if p == t else "XX "
    print(f"{mark} pred={LABELS[p]:8s} true={LABELS[t]:8s}  {text[:40]}")
print(f"ACCURACY {acc:.4f}")
print(f"INFER_VOCAB {num_features_at_infer}  TRAIN_VOCAB {trained_features}")
PYEOF

echo
echo "==> Training, then running the self-check:"
echo "-------------------------------------------------------------"
cd "${WORKDIR}"
python train.py
echo
python check.py || true
echo "-------------------------------------------------------------"
echo
echo "Nothing crashed, but ACCURACY is terrible and INFER_VOCAB != TRAIN_VOCAB."
echo "That is a TOKENIZER MISMATCH. Open runbook.md and fix it."
