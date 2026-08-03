#!/usr/bin/env bash
set -euo pipefail

# SUTA Labs - SURVIVE validator: misleading-stats
# Checks that the student detected the sampling bias and produced a
# corrected analysis + honest write-up.
#
# Run as ec2-user on CentOS Stream 9. Exits 0 only if all checks pass.

WORKDIR="${HOME}/survive-misleading-stats"
VENV="${WORKDIR}/venv"
FAIL=0

echo "=== SURVIVE validator: misleading-stats ==="
echo

# Check 1: corrected_analysis.py exists
if [ -f "${WORKDIR}/corrected_analysis.py" ]; then
  echo "PASS: corrected_analysis.py exists"
else
  echo "FAIL: corrected_analysis.py not found in ${WORKDIR}"
  FAIL=1
fi

# Check 2: corrected_findings.md exists and mentions bias
if [ -f "${WORKDIR}/corrected_findings.md" ]; then
  if grep -qi 'bias' "${WORKDIR}/corrected_findings.md"; then
    echo "PASS: corrected_findings.md exists and mentions bias"
  else
    echo "FAIL: corrected_findings.md exists but does not mention 'bias'"
    FAIL=1
  fi
else
  echo "FAIL: corrected_findings.md not found in ${WORKDIR}"
  FAIL=1
fi

# Check 3: corrected_analysis.py runs (exit 0) and reports a
# stratified / matched comparison.
if [ -f "${WORKDIR}/corrected_analysis.py" ]; then
  # Make sure a usable venv exists (create + install if needed).
  if [ ! -d "${VENV}" ]; then
    echo "INFO: virtual environment missing, creating it..."
    python3.12 -m venv "${VENV}"
  fi

  # shellcheck disable=SC1091
  source "${VENV}/bin/activate"

  # Ensure the stats libraries are present (quiet, idempotent).
  if ! python -c "import numpy, pandas, scipy" >/dev/null 2>&1; then
    echo "INFO: installing numpy/pandas/scipy into the venv..."
    python -m pip install --quiet --upgrade pip
    python -m pip install --quiet numpy pandas scipy
  fi

  OUTPUT="$(cd "${WORKDIR}" && python corrected_analysis.py 2>&1)"
  RC=$?

  deactivate

  if [ "${RC}" -eq 0 ] && echo "${OUTPUT}" | grep -qiE 'stratif|match'; then
    echo "PASS: corrected_analysis.py runs and reports a stratified/matched comparison"
  else
    echo "FAIL: corrected_analysis.py did not run cleanly or did not report a"
    echo "      stratified/matched comparison (exit code ${RC})."
    echo "      ----- script output -----"
    echo "${OUTPUT}"
    echo "      -------------------------"
    FAIL=1
  fi
else
  echo "FAIL: cannot run corrected_analysis.py (file missing)"
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
