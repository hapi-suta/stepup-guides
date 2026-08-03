#!/usr/bin/env bash
# SURVIVE inject: over-parameterized net on a SMALL dataset that has a real
# signal plus label noise, trained with NO regularization for too long. It
# memorizes the training noise (train loss -> ~0) while validation loss stays
# high. A regularized model would learn the signal and generalize.
set -euo pipefail
LAB="$HOME/tier5-overfit-lab"; rm -rf "$LAB"; mkdir -p "$LAB"; cd "$LAB"
cat > train.py <<'PY'
import sys, json, torch, torch.nn as nn
g = torch.Generator().manual_seed(0)
N, D = 40, 8
w = torch.tensor([1.6, -1.2, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0])
def make(n):
    X = torch.randn(n, D, generator=g)
    logits = X @ w + 0.6 * torch.randn(n, generator=g)   # real signal + noise
    return X, (logits > 0).float()
Xtr, ytr = make(N)
Xva, yva = make(N)
dropout = float(sys.argv[1]) if len(sys.argv) > 1 else 0.0
wd      = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
epochs  = int(sys.argv[3])   if len(sys.argv) > 3 else 1500
m = nn.Sequential(nn.Linear(D,256), nn.ReLU(), nn.Dropout(dropout),
                  nn.Linear(256,256), nn.ReLU(), nn.Dropout(dropout), nn.Linear(256,1))
opt = torch.optim.Adam(m.parameters(), lr=0.01, weight_decay=wd)
lossf = nn.BCEWithLogitsLoss()
for _ in range(epochs):
    m.train(); opt.zero_grad(); lossf(m(Xtr).squeeze(1), ytr).backward(); opt.step()
m.eval()
with torch.no_grad():
    tr = lossf(m(Xtr).squeeze(1), ytr).item(); va = lossf(m(Xva).squeeze(1), yva).item()
json.dump({"train_loss": tr, "val_loss": va, "gap": va - tr}, open("metrics.json", "w"))
print(f"train_loss={tr:.4f} val_loss={va:.4f} gap={va-tr:.4f}")
PY
echo "[inject] training with NO regularization (dropout=0, weight_decay=0, 1500 epochs)..."
python3.12 train.py 0.0 0.0 1500
echo "[inject] done - the model memorized the training set. Fix it (runbook), then validate.sh."
