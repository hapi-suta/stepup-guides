#!/usr/bin/env bash
#
# SURVIVE: loss-goes-nan
# Injects a broken PyTorch classifier training script whose learning rate is set
# far too high. The gradients explode, the loss jumps to inf and then nan, and
# the model learns nothing. Your job (see runbook.md) is to diagnose the
# exploding gradients and recover by lowering the learning rate and/or adding
# gradient clipping.
#
# Run this on your lab server as ec2-user. It builds the working dir, a venv,
# installs the CPU-only PyTorch wheel + scikit-learn, writes train.py (with the
# bad learning rate), and runs it so you SEE the loss blow up.
#
set -euo pipefail

WORKDIR="${HOME}/survive-loss-nan"
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

echo "==> Writing train.py (with a BROKEN, too-high learning rate)"
cat > "${WORKDIR}/train.py" <<'PYEOF'
#!/usr/bin/env python3
"""
Tiny text classifier: TF-IDF features -> small PyTorch net. CPU only.

Three toy classes over a handful of short documents. A healthy run drives the
loss DOWN every epoch and ends with a small, finite FINAL_LOSS.

BUG (this is the SURVIVE scenario):
    learning_rate below is set WAY TOO HIGH. Each optimizer step overshoots, the
    gradients explode, and the loss jumps to inf and then nan. The model learns
    nothing. Your job (runbook.md) is to lower the learning rate and/or add
    gradient clipping so the loss converges to a finite number.
"""
import torch
import torch.nn as nn
from sklearn.feature_extraction.text import TfidfVectorizer

torch.manual_seed(0)

texts = [
    "invoice total amount due payment net thirty",
    "invoice balance remit payment remittance enclosed",
    "facture montant paiement solde du",
    "resume skills experience education engineer",
    "curriculum vitae objective senior role references",
    "competences experience formation ingenieur",
    "agreement parties terms conditions governing law",
    "contract terminated party written notice",
    "contrat parties termes conditions droit",
]
labels = [0, 0, 0, 1, 1, 1, 2, 2, 2]  # 0=invoice 1=resume 2=contract

vectorizer = TfidfVectorizer()
X = torch.tensor(vectorizer.fit_transform(texts).toarray(), dtype=torch.float32)
y = torch.tensor(labels, dtype=torch.long)

model = nn.Sequential(
    nn.Linear(X.shape[1], 16),
    nn.ReLU(),
    nn.Linear(16, 3),
)

loss_fn = nn.CrossEntropyLoss()

# BUG: this learning rate is far too high and makes the loss diverge to nan.
# A healthy value for this problem is around 0.05.
learning_rate = 50.0
optimizer = torch.optim.SGD(model.parameters(), lr=learning_rate)

# --- OPTIONAL SAFETY NET (currently OFF) ----------------------------------
# Gradient clipping caps how big a single update can be, which stops an
# exploding-gradient blow-up. It is disabled here. Turning it on is one valid
# fix (see runbook.md). To enable, set use_grad_clip = True.
use_grad_clip = False
clip_value = 1.0

loss = float("nan")
model.train()
for epoch in range(40):
    optimizer.zero_grad()
    logits = model(X)
    loss = loss_fn(logits, y)
    loss.backward()
    if use_grad_clip:
        nn.utils.clip_grad_norm_(model.parameters(), clip_value)
    optimizer.step()
    if epoch % 5 == 0 or epoch == 39:
        print(f"epoch {epoch:2d}  loss {loss.item():.6f}")

print(f"FINAL_LOSS {loss.item():.6f}")
PYEOF

echo
echo "==> Running the broken train.py so you can see the failure:"
echo "-------------------------------------------------------------"
cd "${WORKDIR}"
# Do not let a nonzero exit here stop the script - we WANT you to see it break.
python "${WORKDIR}/train.py" || true
echo "-------------------------------------------------------------"
echo
echo "Notice the loss jumping to inf/nan. Those are EXPLODING GRADIENTS."
echo "Open runbook.md and recover the run."
