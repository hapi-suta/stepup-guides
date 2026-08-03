#!/usr/bin/env bash
set -euo pipefail

# SUTA Labs - SURVIVE validator: governance-gap-audit
# Passes only if the student remediated the gap:
#   - produced an impact assessment for AI-003
#   - produced a human-oversight plan for AI-003
#   - updated the inventory so AI-003 has an owner, an IA, and an oversight plan
#   - the audit tool now reports no gaps (exit 0)
#
# Run as ec2-user on CentOS Stream 9. Exits 0 only if all checks pass.

WORKDIR="${HOME}/survive-governance-gap"
FAIL=0

echo "=== SURVIVE validator: governance-gap-audit ==="
echo

cd "${WORKDIR}" 2>/dev/null || {
  echo "FAIL: working directory ${WORKDIR} not found. Run inject.sh first."
  exit 1
}

# Check 1: an impact assessment file for AI-003 exists and mentions the system.
IA_FILE="$(ls -1 ${WORKDIR}/*AI-003* 2>/dev/null | grep -iE 'impact|ia' | head -1 || true)"
if [ -n "${IA_FILE}" ] && grep -qiE 'impact|harm|oversight' "${IA_FILE}"; then
  echo "PASS: impact assessment for AI-003 exists (${IA_FILE##*/})"
else
  echo "FAIL: no impact-assessment file for AI-003 found (expected a file whose"
  echo "      name contains AI-003 and 'impact' or 'ia', mentioning harms)."
  FAIL=1
fi

# Check 2: a human-oversight plan for AI-003 exists.
OV_FILE="$(ls -1 ${WORKDIR}/*AI-003* 2>/dev/null | grep -iE 'oversight' | head -1 || true)"
if [ -n "${OV_FILE}" ] && grep -qiE 'in the loop|override|stop|oversight' "${OV_FILE}"; then
  echo "PASS: human-oversight plan for AI-003 exists (${OV_FILE##*/})"
else
  echo "FAIL: no human-oversight plan for AI-003 found (expected a file whose"
  echo "      name contains AI-003 and 'oversight')."
  FAIL=1
fi

# Check 3: the inventory row for AI-003 no longer has MISSING in owner,
#          impact_assessment, or oversight_plan.
if [ -f "${WORKDIR}/ai_system_inventory.csv" ]; then
  AI003_LINE="$(grep '^AI-003,' "${WORKDIR}/ai_system_inventory.csv" || true)"
  if [ -z "${AI003_LINE}" ]; then
    echo "FAIL: AI-003 row not found in ai_system_inventory.csv"
    FAIL=1
  elif echo "${AI003_LINE}" | grep -qi 'MISSING'; then
    echo "FAIL: AI-003 inventory row still contains MISSING:"
    echo "      ${AI003_LINE}"
    FAIL=1
  else
    echo "PASS: AI-003 inventory row has no MISSING fields"
  fi
else
  echo "FAIL: ai_system_inventory.csv not found"
  FAIL=1
fi

# Check 4: the audit tool now reports no gaps (exit 0).
if [ -f "${WORKDIR}/audit_inventory.py" ]; then
  if python3 "${WORKDIR}/audit_inventory.py" >/dev/null 2>&1; then
    echo "PASS: audit_inventory.py now reports no governance gaps"
  else
    echo "FAIL: audit_inventory.py still reports governance gaps. Run it to see:"
    echo "      python3 ${WORKDIR}/audit_inventory.py"
    FAIL=1
  fi
else
  echo "FAIL: audit_inventory.py not found"
  FAIL=1
fi

echo
if [ "${FAIL}" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
