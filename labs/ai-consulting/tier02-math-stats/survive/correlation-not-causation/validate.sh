#!/usr/bin/env bash
#
# SURVIVE validator: correlation-not-causation
#
# Checks that the student:
#   1. Wrote corrected_claim.md
#   2. Called out the causation issue AND at least one corrective concept
#      (confounder / lurking variable / company size / randomized / A/B /
#      experiment)
#   3. Wrote confound_check.py and that it runs cleanly (exit 0)
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
#
set -euo pipefail

WORKDIR="${HOME}/survive-corr-causation"
VENV="${WORKDIR}/.venv"
CORRECTED="${WORKDIR}/corrected_claim.md"
CONFOUND="${WORKDIR}/confound_check.py"

PASS=0
FAIL=1
overall="${PASS}"

fail() {
  echo "FAIL: $1"
  overall="${FAIL}"
}

echo "=== Validating SURVIVE: correlation-not-causation ==="

# --- Check 1: corrected_claim.md exists ---
if [ -f "${CORRECTED}" ]; then
  echo "OK:   corrected_claim.md exists"
else
  fail "corrected_claim.md not found at ${CORRECTED}"
fi

# --- Check 2: content addresses the causation issue + a corrective concept ---
if [ -f "${CORRECTED}" ]; then
  if grep -qi 'causation' "${CORRECTED}"; then
    echo "OK:   corrected_claim.md mentions causation"
  else
    fail "corrected_claim.md does not mention 'causation'"
  fi

  if grep -qiE 'confound|lurking|company size|randomiz|a/b|experiment' "${CORRECTED}"; then
    echo "OK:   corrected_claim.md names a corrective concept (confounder / randomized test / experiment)"
  else
    fail "corrected_claim.md is missing a corrective concept (confound, lurking, company size, randomized, A/B, or experiment)"
  fi
fi

# --- Check 3: confound_check.py exists and runs cleanly ---
if [ -f "${CONFOUND}" ]; then
  echo "OK:   confound_check.py exists"

  # Make sure a venv with numpy/pandas is available to run it.
  if [ ! -d "${VENV}" ]; then
    echo "INFO: no venv found, creating one to run confound_check.py"
    python3.12 -m venv "${VENV}"
    # shellcheck disable=SC1091
    source "${VENV}/bin/activate"
    python -m pip install --quiet --upgrade pip
    python -m pip install --quiet numpy pandas
  else
    # shellcheck disable=SC1091
    source "${VENV}/bin/activate"
  fi

  echo "INFO: running confound_check.py ..."
  if ( cd "${WORKDIR}" && python confound_check.py >/dev/null 2>&1 ); then
    echo "OK:   confound_check.py ran successfully (exit 0)"
  else
    fail "confound_check.py did not run cleanly (non-zero exit)"
  fi

  deactivate || true
else
  fail "confound_check.py not found at ${CONFOUND}"
fi

echo "----------------------------------------------------"
if [ "${overall}" -eq "${PASS}" ]; then
  echo "RESULT: PASS - you caught the confound and corrected the claim."
  exit 0
else
  echo "RESULT: FAIL - review the runbook and try again."
  exit 1
fi
