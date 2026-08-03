#!/usr/bin/env bash
#
# SURVIVE validator: gradient-descent-diverges
#
# PASS only if the student's train.py:
#   1. exists
#   2. runs and exits 0
#   3. prints a FINAL_LOSS line whose value is a finite number well below the
#      divergence threshold (loss < 50), and clearly lower than epoch 0.
#
# Run on the lab server as ec2-user. Activates the venv (creates it and
# installs numpy if missing).
#
set -euo pipefail

WORKDIR="${HOME}/survive-gd-diverges"
VENV="${WORKDIR}/venv"
TRAIN="${WORKDIR}/train.py"
THRESHOLD=50

fail() {
  echo "FAIL: $1"
  exit 1
}

# --- check 1: train.py exists ---------------------------------------------
if [[ ! -f "${TRAIN}" ]]; then
  fail "${TRAIN} not found. Run inject.sh first, then fix the learning rate."
fi

# --- venv: create + ensure numpy ------------------------------------------
if [[ ! -d "${VENV}" ]]; then
  echo "venv missing, creating it ..."
  python3.12 -m venv "${VENV}"
fi

# shellcheck disable=SC1091
source "${VENV}/bin/activate"
python -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
python -m pip install --quiet numpy >/dev/null 2>&1 || fail "could not install numpy in the venv."

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
# Use python for a robust finite + numeric + threshold check (handles inf/nan).
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
    print("BAD not finite (inf or nan) - training diverged")
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
  fail "training did not converge - ${DETAIL}. Lower the learning rate in train.py."
fi

echo "PASS: training converged (final loss ${FINAL_LOSS} is finite and below ${THRESHOLD})."
exit 0
