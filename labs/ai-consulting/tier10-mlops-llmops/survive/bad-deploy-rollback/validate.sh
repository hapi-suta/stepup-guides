#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# Validator for SURVIVE scenario: bad-deploy-rollback
# Checks the student rolled back and documented the incident:
#   - the current production model is v1 (the known-good one), not v2
#   - healthcheck.py exits 0 (production serves again)
#   - rollback_incident.md exists and mentions rollback, the bad deploy, and v1
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-bad-deploy"
FINDINGS="${WORKDIR}/rollback_incident.md"

PASS=0; FAIL=1; overall="${PASS}"
fail() { echo "FAIL: $1"; overall="${FAIL}"; }

echo "=== Validating SURVIVE: bad-deploy-rollback ==="

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

# --- production must be v1 ----------------------------------------------------
CURRENT="$( cd "${WORKDIR}" && python registry.py current 2>/dev/null | grep -i 'production run_id' | grep -oE 'v[0-9]+' || true )"
if [ "${CURRENT}" = "v1" ]; then
  echo "OK:   production is v1 (rolled back to the known-good model)"
elif [ "${CURRENT}" = "v2" ]; then
  fail "production is still v2 (the broken model) - you have not rolled back"
else
  fail "could not determine the current production model"
fi

# --- healthcheck must pass ----------------------------------------------------
if ( cd "${WORKDIR}" && python healthcheck.py ) >/dev/null 2>&1; then
  echo "OK:   healthcheck passes (production serves again)"
else
  fail "healthcheck still fails - production is not healthy"
fi

# --- incident write-up -------------------------------------------------------
if [ -f "${FINDINGS}" ]; then
  echo "OK:   rollback_incident.md exists"
  if grep -qiE "rollback|rolled back" "${FINDINGS}"; then
    echo "OK:   incident mentions the rollback"
  else
    fail "incident does not mention the rollback"
  fi
  if grep -qiE "v1" "${FINDINGS}"; then
    echo "OK:   incident names v1 as the known-good model"
  else
    fail "incident does not name v1"
  fi
  if grep -qiE "deploy|healthcheck|broken|corrupt" "${FINDINGS}"; then
    echo "OK:   incident describes the bad deploy"
  else
    fail "incident does not describe the bad deploy"
  fi
else
  fail "rollback_incident.md not found at ${FINDINGS}"
fi

# --- verdict -----------------------------------------------------------------
if [ "${overall}" -eq "${PASS}" ]; then
  echo "RESULT: PASS - bad deploy rolled back, production healthy, incident documented"
  exit 0
else
  echo "RESULT: FAIL - see FAIL lines above"
  exit 1
fi
