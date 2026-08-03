#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# Validator for SURVIVE scenario: concept-drift
# Checks the student detected the drift and recovered the model:
#   - drift_findings.md exists and mentions drift/shift, states the decision
#     (retrain, or retire with justification), and describes monitoring
#   - retrain.py exists, runs exit 0, and prints a recovered accuracy that is
#     materially above the drifted ~0.63 (threshold: >= 0.80)
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-concept-drift"
FINDINGS="${WORKDIR}/drift_findings.md"
RETRAIN="${WORKDIR}/retrain.py"

PASS=0; FAIL=1; overall="${PASS}"
fail() { echo "FAIL: $1"; overall="${FAIL}"; }

echo "=== Validating SURVIVE: concept-drift ==="

# --- findings file -----------------------------------------------------------
if [ -f "${FINDINGS}" ]; then
  echo "OK:   drift_findings.md exists"
else
  fail "drift_findings.md not found at ${FINDINGS}"
fi

if [ -f "${FINDINGS}" ]; then
  if grep -qiE "drift|shift" "${FINDINGS}"; then
    echo "OK:   findings mention drift or shift"
  else
    fail "findings do not mention 'drift' or 'shift'"
  fi

  if grep -qiE "retrain|re-train|retire" "${FINDINGS}"; then
    echo "OK:   findings state the retrain (or justified retire) decision"
  else
    fail "findings do not state a retrain/retire decision"
  fi

  if grep -qiE "monitor|going forward|alert|threshold|retrain" "${FINDINGS}"; then
    echo "OK:   findings describe monitoring going forward"
  else
    fail "findings do not describe monitoring going forward"
  fi
fi

# --- retrain -----------------------------------------------------------------
if [ -f "${RETRAIN}" ]; then
  echo "OK:   retrain.py exists"
else
  fail "retrain.py not found at ${RETRAIN}"
fi

if [ -f "${RETRAIN}" ]; then
  if [ -f "${WORKDIR}/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "${WORKDIR}/.venv/bin/activate"
  else
    fail "venv not found at ${WORKDIR}/.venv - run inject.sh first"
  fi

  OUT_FILE="$(mktemp)"
  if ( cd "${WORKDIR}" && python retrain.py ) > "${OUT_FILE}" 2>&1; then
    echo "OK:   retrain.py runs clean"

    # Prefer a recovered/retrained accuracy line; fall back to any accuracy.
    ACC_LINE="$(grep -iE 'recovered|retrained_accuracy|recent|accuracy' "${OUT_FILE}" | tail -n 1 || true)"
    if [ -n "${ACC_LINE}" ]; then
      ACC="$(printf '%s\n' "${ACC_LINE}" | grep -oE '[0-9]+\.[0-9]+' | tail -n 1 || true)"
      if [ -n "${ACC}" ]; then
        if awk -v a="${ACC}" 'BEGIN { exit !(a >= 0.80) }'; then
          echo "OK:   recovered accuracy ${ACC} is materially above the drifted ~0.63"
        else
          fail "recovered accuracy ${ACC} is not materially above ~0.63 (need >= 0.80)"
        fi
      else
        fail "could not parse an accuracy number from retrain.py output"
      fi
    else
      fail "retrain.py printed no accuracy line"
    fi
  else
    echo "----- retrain.py output -----"
    cat "${OUT_FILE}"
    echo "-----------------------------"
    fail "retrain.py exited non-zero"
  fi
  rm -f "${OUT_FILE}"
fi

# --- verdict -----------------------------------------------------------------
if [ "${overall}" -eq "${PASS}" ]; then
  echo "RESULT: PASS - drift detected, decision justified, and accuracy recovered"
  exit 0
else
  echo "RESULT: FAIL - see FAIL lines above"
  exit 1
fi
