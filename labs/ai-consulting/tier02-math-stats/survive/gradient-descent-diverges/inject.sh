#!/usr/bin/env bash
#
# SURVIVE: gradient-descent-diverges
# Injects a broken gradient descent line-fit training script whose learning
# rate is set way too high, so the loss diverges to inf/nan.
#
# Run this on your lab server as ec2-user. It builds the working dir, a venv,
# installs numpy, writes train.py (with the bad learning rate), and runs it so
# you SEE the loss explode. Your job (see runbook.md) is to fix the learning
# rate so the loss converges.
#
set -euo pipefail

WORKDIR="${HOME}/survive-gd-diverges"
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

echo "==> Upgrading pip and installing numpy"
python -m pip install --quiet --upgrade pip
python -m pip install --quiet numpy

echo "==> Writing train.py (with a BROKEN learning rate)"
cat > "${WORKDIR}/train.py" <<'PYEOF'
#!/usr/bin/env python3
"""
Gradient descent line fitter.

We fit a straight line  y = w*x + b  to some noisy data by minimizing the
mean squared error (MSE) loss with gradient descent.

The data is generated from the TRUE line  y = 2*x + 5  plus a little noise,
so a healthy training run should drive:
    w  ->  about 2.0
    b  ->  about 5.0
    loss -> small and shrinking every epoch

BUG (this is the SURVIVE scenario):
    learning_rate below is set WAY TOO HIGH. Each step overshoots the minimum
    and bounces further away, so the loss grows every epoch and blows up to
    inf/nan. Your job is to lower it (see runbook.md).
"""

import numpy as np

# ---- data -----------------------------------------------------------------
# Fixed seed so everyone sees the same numbers.
np.random.seed(0)
x = np.linspace(0, 10, 50)                # 50 points from 0 to 10
noise = np.random.randn(50)               # small random noise
y = 2 * x + 5 + noise                     # true line: y = 2x + 5 (+ noise)

n = len(x)

# ---- model parameters (start at zero) -------------------------------------
w = 0.0
b = 0.0

# ---- training settings ----------------------------------------------------
# BUG: this learning rate is far too large for this data and diverges.
# A good value for this problem is around 0.01.
learning_rate = 0.5
epochs = 30

# ---- training loop --------------------------------------------------------
loss = float("nan")
for epoch in range(epochs):
    # Prediction and error for every data point.
    y_pred = w * x + b
    error = y_pred - y

    # Mean squared error loss.
    loss = np.mean(error ** 2)

    # Gradients of the MSE loss with respect to w and b.
    grad_w = (2.0 / n) * np.sum(error * x)
    grad_b = (2.0 / n) * np.sum(error)

    # Gradient descent update step.
    w = w - learning_rate * grad_w
    b = b - learning_rate * grad_b

    print(f"epoch {epoch:2d}  loss {loss:.6f}  w {w:.6f}  b {b:.6f}")

# Final line for the validator to grep. When broken this prints inf or nan.
print(f"FINAL_LOSS {loss:.6f}")
PYEOF

echo
echo "==> Running the broken train.py so you can see the failure:"
echo "-------------------------------------------------------------"
cd "${WORKDIR}"
# Do not let a nonzero exit here stop the script - we WANT you to see it break.
python "${WORKDIR}/train.py" || true
echo "-------------------------------------------------------------"
echo
echo "Notice the loss growing every epoch and ending as inf or nan."
echo "That runaway loss is DIVERGENCE. Open runbook.md and fix it."
