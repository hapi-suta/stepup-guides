#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# Validator for SURVIVE scenario: cost-runaway
# Proves the student's budget guard holds under the runaway load:
#   - guarded_serve.py exists and exposes a serve() function
#   - starting from a clean metrics log, the runaway loop against guarded_serve
#     refuses calls once the budget is spent
#   - after the runaway, cost_alert.py stays WITHIN a slightly-padded budget
#     (i.e. the guard capped spend instead of letting it blow out)
#   - cost_findings.md exists and mentions budget/cap, runaway, and a control
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-cost-runaway"
GUARD="${WORKDIR}/guarded_serve.py"
FINDINGS="${WORKDIR}/cost_findings.md"
BUDGET="1.00"
# The guard caps at $BUDGET; allow one over-budget call of slack before it trips.
PAD_BUDGET="1.05"

PASS=0; FAIL=1; overall="${PASS}"
fail() { echo "FAIL: $1"; overall="${FAIL}"; }

echo "=== Validating SURVIVE: cost-runaway ==="

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

# --- guard exists ------------------------------------------------------------
if [ -f "${GUARD}" ]; then
  echo "OK:   guarded_serve.py exists"
  if grep -qE "def serve" "${GUARD}"; then
    echo "OK:   guarded_serve.py exposes a serve() function"
  else
    fail "guarded_serve.py has no serve() function for the runaway to call"
  fi
else
  fail "guarded_serve.py not found at ${GUARD}"
fi

# --- run the runaway against the guarded path from a clean log ---------------
if [ -f "${GUARD}" ]; then
  ( cd "${WORKDIR}" && rm -f llm_metrics.jsonl )
  OUT_FILE="$(mktemp)"
  if ( cd "${WORKDIR}" && python runaway.py guarded_serve 5000 ) > "${OUT_FILE}" 2>&1; then
    REFUSED="$(grep -oE 'refused: [0-9]+' "${OUT_FILE}" | grep -oE '[0-9]+' || echo 0)"
    if [ "${REFUSED:-0}" -gt 0 ]; then
      echo "OK:   guard refused ${REFUSED} calls once the budget was spent"
    else
      fail "guard refused 0 calls - it did not cap the runaway"
    fi
  else
    echo "----- runaway output -----"; cat "${OUT_FILE}"; echo "--------------------------"
    fail "runaway against guarded_serve did not run cleanly"
  fi
  rm -f "${OUT_FILE}"

  # --- cost must stay within the padded budget -------------------------------
  if ( cd "${WORKDIR}" && python cost_alert.py --budget "${PAD_BUDGET}" ) >/dev/null 2>&1; then
    echo "OK:   post-runaway spend stayed within the \$${PAD_BUDGET} cap (guard held)"
  else
    ( cd "${WORKDIR}" && python cost_alert.py --budget "${PAD_BUDGET}" ) || true
    fail "spend blew past the cap even with the guard - the guard did not hold"
  fi
fi

# --- findings ----------------------------------------------------------------
if [ -f "${FINDINGS}" ]; then
  echo "OK:   cost_findings.md exists"
  if grep -qiE "budget|cap" "${FINDINGS}"; then
    echo "OK:   findings mention the budget/cap"
  else
    fail "findings do not mention a budget or cap"
  fi
  if grep -qiE "runaway|loop|blowout|2am|retry" "${FINDINGS}"; then
    echo "OK:   findings describe the runaway"
  else
    fail "findings do not describe the runaway"
  fi
  if grep -qiE "rate.?limit|token count|caching|guard|refuse|circuit" "${FINDINGS}"; then
    echo "OK:   findings name a control (rate limit / token count / cache / guard)"
  else
    fail "findings do not name a cost control"
  fi
else
  fail "cost_findings.md not found at ${FINDINGS}"
fi

# --- verdict -----------------------------------------------------------------
if [ "${overall}" -eq "${PASS}" ]; then
  echo "RESULT: PASS - budget guard holds under the runaway, spend capped, documented"
  exit 0
else
  echo "RESULT: FAIL - see FAIL lines above"
  exit 1
fi
