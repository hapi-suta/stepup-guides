#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# Validator for SURVIVE scenario: prompt-drift
# Checks the student fixed the drift and documented it:
#   - prompt_regression.py now exits 0 (golden set passes)
#   - the prompt template no longer forces one-word/brief answers
#   - prompt_drift_findings.md exists and mentions prompt drift, the golden set
#     / regression test, and versioning or restoring the prompt
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-prompt-drift"
FINDINGS="${WORKDIR}/prompt_drift_findings.md"
TEMPLATE="${WORKDIR}/prompt_template.txt"

PASS=0; FAIL=1; overall="${PASS}"
fail() { echo "FAIL: $1"; overall="${FAIL}"; }

echo "=== Validating SURVIVE: prompt-drift ==="

if [ ! -d "${WORKDIR}" ]; then
  echo "FAIL: ${WORKDIR} not found - run inject.sh first"
  exit 1
fi

if [ -f "${WORKDIR}/.venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "${WORKDIR}/.venv/bin/activate"
else
  fail "venv not found at ${WORKDIR}/.venv - run inject.sh first"
fi

# --- the drifted instruction must be gone ------------------------------------
if [ -f "${TEMPLATE}" ]; then
  if grep -qiE "one word|single word|brief|concise|one sentence" "${TEMPLATE}"; then
    fail "prompt_template.txt still forces a terse answer - the drift is not removed"
  else
    echo "OK:   prompt template no longer forces a terse answer"
  fi
else
  echo "OK:   prompt_template.txt removed (default template restored)"
fi

# --- regression suite must pass ----------------------------------------------
OUT_FILE="$(mktemp)"
if ( cd "${WORKDIR}" && python prompt_regression.py ) > "${OUT_FILE}" 2>&1; then
  echo "OK:   prompt regression suite passes (golden set is green)"
else
  echo "----- prompt_regression.py output -----"
  cat "${OUT_FILE}"
  echo "---------------------------------------"
  fail "prompt regression suite still fails - the golden set is not green"
fi
rm -f "${OUT_FILE}"

# --- findings ----------------------------------------------------------------
if [ -f "${FINDINGS}" ]; then
  echo "OK:   prompt_drift_findings.md exists"
  if grep -qiE "prompt drift|prompt.*chang|drift" "${FINDINGS}"; then
    echo "OK:   findings mention prompt drift"
  else
    fail "findings do not mention prompt drift"
  fi
  if grep -qiE "golden|regression" "${FINDINGS}"; then
    echo "OK:   findings mention the golden set / regression test"
  else
    fail "findings do not mention the golden set or regression test"
  fi
  if grep -qiE "version|restore|revert|rollback|CI" "${FINDINGS}"; then
    echo "OK:   findings name a prevention (versioning/restore/CI gate)"
  else
    fail "findings do not name a prevention (versioning, restore, or CI gate)"
  fi
else
  fail "prompt_drift_findings.md not found at ${FINDINGS}"
fi

# --- verdict -----------------------------------------------------------------
if [ "${overall}" -eq "${PASS}" ]; then
  echo "RESULT: PASS - prompt drift detected, corrected, golden set green, documented"
  exit 0
else
  echo "RESULT: FAIL - see FAIL lines above"
  exit 1
fi
