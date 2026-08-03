#!/usr/bin/env bash
#
# SURVIVE validator: tokenizer-mismatch
#
# PASS only if the student's check.py:
#   1. exists
#   2. runs and exits 0
#   3. reports the SAME vocabulary size at inference as at training
#      (INFER_VOCAB == TRAIN_VOCAB), proving the saved vectorizer is reused, AND
#   4. reports high accuracy on the held-out set (ACCURACY >= 0.80).
#
# Run on the lab server as ec2-user. Activates the venv (creates + installs
# CPU torch + scikit-learn if missing). Retrains first so the model + saved
# vectorizer exist.
#
set -euo pipefail

WORKDIR="${HOME}/survive-tokenizer-mismatch"
VENV="${WORKDIR}/venv"
CHECK="${WORKDIR}/check.py"
TRAIN="${WORKDIR}/train.py"
MIN_ACC=0.80

fail() {
  echo "FAIL: $1"
  exit 1
}

if [[ ! -f "${CHECK}" || ! -f "${TRAIN}" ]]; then
  fail "check.py or train.py not found. Run inject.sh first, then fix check.py."
fi

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

# Retrain so model.pt + vectorizer.pkl exist and are current.
echo "Retraining to refresh model.pt and vectorizer.pkl ..."
if ! (cd "${WORKDIR}" && python train.py >/dev/null 2>&1); then
  fail "train.py crashed during validation retrain."
fi

echo "Running your check.py ..."
OUTPUT=""
if ! OUTPUT="$(cd "${WORKDIR}" && python check.py 2>&1)"; then
  echo "${OUTPUT}"
  fail "check.py exited with a nonzero status (it crashed)."
fi
echo "${OUTPUT}"

ACC_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^ACCURACY ' | tail -n 1 || true)"
VOCAB_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^INFER_VOCAB ' | tail -n 1 || true)"
if [[ -z "${ACC_LINE}" || -z "${VOCAB_LINE}" ]]; then
  fail "check.py must print an 'ACCURACY <n>' line and an 'INFER_VOCAB <n>  TRAIN_VOCAB <n>' line."
fi

ACC="$(printf '%s\n' "${ACC_LINE}" | awk '{print $2}')"
INFER_VOCAB="$(printf '%s\n' "${VOCAB_LINE}" | awk '{print $2}')"
TRAIN_VOCAB="$(printf '%s\n' "${VOCAB_LINE}" | awk '{print $4}')"

# --- check: vocab sizes match (proves saved vectorizer is reused) ----------
if [[ "${INFER_VOCAB}" != "${TRAIN_VOCAB}" ]]; then
  fail "inference vocab (${INFER_VOCAB}) != training vocab (${TRAIN_VOCAB}) - tokenizer still mismatched. Reuse the saved vectorizer."
fi

# --- check: accuracy high enough -------------------------------------------
CHECK_ACC="$(python - "$ACC" "$MIN_ACC" <<'PYEOF'
import math
import sys
try:
    acc = float(sys.argv[1]); floor = float(sys.argv[2])
except ValueError:
    print("BAD not a number"); sys.exit(0)
if not math.isfinite(acc):
    print("BAD accuracy not finite"); sys.exit(0)
if acc < floor:
    print(f"BAD accuracy {acc} below {floor}"); sys.exit(0)
print(f"OK {acc}")
PYEOF
)"

STATUS="$(printf '%s\n' "${CHECK_ACC}" | awk '{print $1}')"
DETAIL="$(printf '%s\n' "${CHECK_ACC}" | cut -d' ' -f2-)"
if [[ "${STATUS}" != "OK" ]]; then
  fail "accuracy still poor - ${DETAIL}. The tokenizer mismatch is not fully fixed."
fi

echo "PASS: tokenizer mismatch fixed (vocab matches at ${TRAIN_VOCAB}, accuracy ${ACC})."
exit 0
