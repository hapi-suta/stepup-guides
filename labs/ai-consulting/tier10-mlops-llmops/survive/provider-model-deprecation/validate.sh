#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# Validator for SURVIVE scenario: provider-model-deprecation
# Checks the student cut over and documented it:
#   - the active model version is a SUPPORTED one (not the deprecated 2024 model)
#   - probe.py exits 0 (the app can reach its model again)
#   - deprecation_cutover.md exists and mentions the deprecation, the cutover /
#     model version, and a prevention (abstraction / fallback / versioning)
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-model-deprecation"
FINDINGS="${WORKDIR}/deprecation_cutover.md"
DEPRECATED="support-model-2024-01"

PASS=0; FAIL=1; overall="${PASS}"
fail() { echo "FAIL: $1"; overall="${FAIL}"; }

echo "=== Validating SURVIVE: provider-model-deprecation ==="

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

# --- active version must not be the deprecated one ---------------------------
ACTIVE="$( cd "${WORKDIR}" && python model_registry.py active 2>/dev/null | grep -i 'active model version' | awk '{print $NF}' || true )"
if [ -z "${ACTIVE}" ]; then
  fail "could not determine the active model version"
elif [ "${ACTIVE}" = "${DEPRECATED}" ]; then
  fail "active version is still the deprecated ${DEPRECATED} - you have not cut over"
else
  echo "OK:   active version is ${ACTIVE} (cut over off the deprecated model)"
fi

# --- probe must pass ---------------------------------------------------------
if ( cd "${WORKDIR}" && python probe.py ) >/dev/null 2>&1; then
  echo "OK:   health probe passes (app can reach its model again)"
else
  fail "health probe still fails - the app cannot reach its model"
fi

# --- cutover write-up --------------------------------------------------------
if [ -f "${FINDINGS}" ]; then
  echo "OK:   deprecation_cutover.md exists"
  if grep -qiE "deprecat|retire" "${FINDINGS}"; then
    echo "OK:   write-up mentions the deprecation"
  else
    fail "write-up does not mention the deprecation"
  fi
  if grep -qiE "cut ?over|promot|model version|2025" "${FINDINGS}"; then
    echo "OK:   write-up describes the cutover to a new version"
  else
    fail "write-up does not describe the cutover"
  fi
  if grep -qiE "abstraction|fallback|version|registry|multi.?provider|not lock" "${FINDINGS}"; then
    echo "OK:   write-up names a prevention (abstraction/fallback/versioning)"
  else
    fail "write-up does not name a prevention"
  fi
else
  fail "deprecation_cutover.md not found at ${FINDINGS}"
fi

# --- verdict -----------------------------------------------------------------
if [ "${overall}" -eq "${PASS}" ]; then
  echo "RESULT: PASS - cut over to a supported model version, probe healthy, documented"
  exit 0
else
  echo "RESULT: FAIL - see FAIL lines above"
  exit 1
fi
