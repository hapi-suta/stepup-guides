#!/usr/bin/env bash
#
# SURVIVE validator: loss-goes-nan
#
# PASS only if the student's train.py:
#   1. exists
#   2. runs and exits 0
#   3. prints a FINAL_LOSS line whose value is a finite number (not inf/nan)
#      and is small (loss < 1.0), proving the training recovered and converged.
#
# Run on the lab server as ec2-user. Activates the venv (creates it and installs
# CPU torch + scikit-learn if missing).
#
set -euo pipefail

WORKDIR="${HOME}/survive-loss-nan"
VENV="${WORKDIR}/venv"
TRAIN="${WORKDIR}/train.py"
THRESHOLD=1.0

fail() {
  echo "FAIL: $1"
  exit 1
}

# --- check 1: train.py exists ---------------------------------------------
if [[ ! -f "${TRAIN}" ]]; then
  fail "${TRAIN} not found. Run inject.sh first, then fix the training script."
fi

# --- venv: create + ensure deps -------------------------------------------
if [[ ! -d "${VENV}" ]]; then
  echo "venv missing, creating it ..."
  python3.12 -m venv "${VENV}"
fi

# shellcheck disable=SC1091
source "${VENV}/bin/activate"
python -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
python -m pip install --quiet --index-url https://download.pytorch.org/whl/cpu torch >/dev/null 2>&1 \
  || fail "could not install CPU torch in the venv."
python -m pip install --quiet scikit-learn >/dev/null 2>&1 \
  || fail "could not install scikit-learn in the venv."

# --- check 2: run train.py, capture output, require exit 0 -----------------
echo "Running your train.py ..."
OUTPUT=""
if ! OUTPUT="$(cd "${WORKDIR}" && python train.py 2>&1)"; then
  echo "${OUTPUT}"
  fail "train.py exited with a nonzero status (it crashed)."
fi

# --- extract FINAL_LOSS ----------------------------------------------------
FINAL_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^FINAL_LOSS ' | tail -n 1 || true)"
if [[ -z "${FINAL_LINE}" ]]; then
  echo "${OUTPUT}"
  fail "no FINAL_LOSS line printed. train.py must print 'FINAL_LOSS <number>'."
fi

FINAL_LOSS="$(printf '%s\n' "${FINAL_LINE}" | awk '{print $2}')"
echo "Final loss reported: ${FINAL_LOSS}"

# --- check 3: finite and below threshold -----------------------------------
CHECK="$(python - "$FINAL_LOSS" "$THRESHOLD" <<'PYEOF'
import math
import sys

raw = sys.argv[1]
threshold = float(sys.argv[2])
try:
    value = float(raw)
except ValueError:
    print("BAD not a number")
    sys.exit(0)
if not math.isfinite(value):
    print("BAD not finite (inf or nan) - gradients still exploding")
    sys.exit(0)
if value >= threshold:
    print(f"BAD loss {value} is not below threshold {threshold}")
    sys.exit(0)
print(f"OK {value}")
PYEOF
)"

STATUS="$(printf '%s\n' "${CHECK}" | awk '{print $1}')"
DETAIL="$(printf '%s\n' "${CHECK}" | cut -d' ' -f2-)"

if [[ "${STATUS}" != "OK" ]]; then
  fail "training did not recover - ${DETAIL}. Lower the learning rate and/or enable gradient clipping."
fi

echo "PASS: training recovered (final loss ${FINAL_LOSS} is finite and below ${THRESHOLD})."
exit 0
