#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# Validator for SURVIVE scenario: data-leakage
# Checks the student corrected the leaky model:
#   - leakage_findings.md exists and names the leaked feature (refund_issued),
#     mentions leakage, and mentions prediction-time availability
#   - honest_train.py exists, runs exit 0, and reports accuracy < 0.95
#     (materially below the naive ~0.99)
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-data-leakage"
FINDINGS="${WORKDIR}/leakage_findings.md"
HONEST="${WORKDIR}/honest_train.py"

PASS=0; FAIL=1; overall="${PASS}"
fail() { echo "FAIL: $1"; overall="${FAIL}"; }

echo "=== Validating SURVIVE: data-leakage ==="

# --- findings file -----------------------------------------------------------
if [ -f "${FINDINGS}" ]; then
  echo "OK:   leakage_findings.md exists"
else
  fail "leakage_findings.md not found at ${FINDINGS}"
fi

if [ -f "${FINDINGS}" ]; then
  if grep -qi "refund_issued" "${FINDINGS}"; then
    echo "OK:   findings name the leaked feature (refund_issued)"
  else
    fail "findings do not name the leaked feature 'refund_issued'"
  fi

  if grep -qiE "leak" "${FINDINGS}"; then
    echo "OK:   findings mention leakage"
  else
    fail "findings do not mention 'leak'/'leakage'"
  fi

  if grep -qiE "prediction time|prediction-time|not available|not known|not knowable|after.*resolved|after.*investigat" "${FINDINGS}"; then
    echo "OK:   findings mention prediction-time availability"
  else
    fail "findings do not explain the feature is unavailable at prediction time"
  fi
fi

# --- honest training ---------------------------------------------------------
if [ -f "${HONEST}" ]; then
  echo "OK:   honest_train.py exists"
else
  fail "honest_train.py not found at ${HONEST}"
fi

if [ -f "${HONEST}" ]; then
  # Activate the venv the injector created so scikit-learn is importable.
  if [ -f "${WORKDIR}/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "${WORKDIR}/.venv/bin/activate"
  else
    fail "venv not found at ${WORKDIR}/.venv - run inject.sh first"
  fi

  OUT_FILE="$(mktemp)"
  if ( cd "${WORKDIR}" && python honest_train.py ) > "${OUT_FILE}" 2>&1; then
    echo "OK:   honest_train.py runs clean"

    # Pull the reported accuracy (last accuracy line) and compare to 0.95.
    ACC_LINE="$(grep -iE 'accuracy' "${OUT_FILE}" | tail -n 1 || true)"
    if [ -n "${ACC_LINE}" ]; then
      ACC="$(printf '%s\n' "${ACC_LINE}" | grep -oE '[0-9]+\.[0-9]+' | tail -n 1 || true)"
      if [ -n "${ACC}" ]; then
        if awk -v a="${ACC}" 'BEGIN { exit !(a < 0.95) }'; then
          echo "OK:   honest accuracy ${ACC} is materially below the naive 0.99"
        else
          fail "honest accuracy ${ACC} is not below 0.95 - is the leak really dropped?"
        fi
      else
        fail "could not parse an accuracy number from honest_train.py output"
      fi
    else
      fail "honest_train.py printed no accuracy line"
    fi
  else
    echo "----- honest_train.py output -----"
    cat "${OUT_FILE}"
    echo "----------------------------------"
    fail "honest_train.py exited non-zero"
  fi
  rm -f "${OUT_FILE}"
fi

# --- verdict -----------------------------------------------------------------
if [ "${overall}" -eq "${PASS}" ]; then
  echo "RESULT: PASS - leak identified, dropped, and honest metrics reported"
  exit 0
else
  echo "RESULT: FAIL - see FAIL lines above"
  exit 1
fi
