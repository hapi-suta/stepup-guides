#!/usr/bin/env bash
set -euo pipefail

# SUTA Labs - SURVIVE validator: biased-output-incident
# Passes only if the student:
#   - filed an incident report that mentions bias and root cause
#   - remediated so the fairness monitor now passes (ratio >= 0.80, exit 0)
#
# Run as ec2-user on CentOS Stream 9. Exits 0 only if all checks pass.

WORKDIR="${HOME}/survive-biased-output"
VENV="${WORKDIR}/venv"
FAIL=0

echo "=== SURVIVE validator: biased-output-incident ==="
echo

cd "${WORKDIR}" 2>/dev/null || {
  echo "FAIL: working directory ${WORKDIR} not found. Run inject.sh first."
  exit 1
}

# Check 1: an incident report exists and covers the essentials.
INC_FILE="$(ls -1 ${WORKDIR}/*incident* 2>/dev/null | head -1 || true)"
if [ -n "${INC_FILE}" ]; then
  if grep -qi 'bias' "${INC_FILE}" && grep -qiE 'root cause|proxy|feature' "${INC_FILE}"; then
    echo "PASS: incident report exists and covers bias + root cause (${INC_FILE##*/})"
  else
    echo "FAIL: incident report ${INC_FILE##*/} must mention 'bias' and a root"
    echo "      cause (e.g. 'proxy' or 'feature')."
    FAIL=1
  fi
else
  echo "FAIL: no incident report found (expected a file whose name contains"
  echo "      'incident')."
  FAIL=1
fi

# Check 2: the fairness monitor now passes (ratio >= 0.80, exit 0).
if [ ! -d "${VENV}" ]; then
  echo "INFO: virtual environment missing, creating it..."
  python3.12 -m venv "${VENV}"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
if ! python -c "import numpy, pandas, sklearn" >/dev/null 2>&1; then
  echo "INFO: installing numpy/pandas/scikit-learn into the venv..."
  python -m pip install --quiet --upgrade pip
  python -m pip install --quiet numpy pandas scikit-learn
fi

if (cd "${WORKDIR}" && python fairness_monitor.py) >/dev/null 2>&1; then
  echo "PASS: fairness monitor now reports a fair model (ratio >= 0.80)"
else
  echo "FAIL: fairness monitor still ALERTs (ratio < 0.80). Remediate the model"
  echo "      (revert to the balanced version / fix the feature set), then retry."
  FAIL=1
fi
deactivate

echo
if [ "${FAIL}" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
