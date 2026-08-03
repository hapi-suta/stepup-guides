#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# Validator for SURVIVE scenario: class-imbalance
# Checks the student exposed and fixed the imbalance:
#   - imbalance_findings.md exists and mentions imbalance, recall, confusion,
#     and a fix (class_weight/balanced/resample/oversampl/SMOTE)
#   - balanced_train.py exists, runs exit 0, and prints a positive-class recall
#     that is materially above the naive ~0.05 (threshold: >= 0.40)
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-class-imbalance"
FINDINGS="${WORKDIR}/imbalance_findings.md"
BALANCED="${WORKDIR}/balanced_train.py"

PASS=0; FAIL=1; overall="${PASS}"
fail() { echo "FAIL: $1"; overall="${FAIL}"; }

echo "=== Validating SURVIVE: class-imbalance ==="

# --- findings file -----------------------------------------------------------
if [ -f "${FINDINGS}" ]; then
  echo "OK:   imbalance_findings.md exists"
else
  fail "imbalance_findings.md not found at ${FINDINGS}"
fi

if [ -f "${FINDINGS}" ]; then
  if grep -qiE "imbalance|imbalanced" "${FINDINGS}"; then
    echo "OK:   findings mention imbalance"
  else
    fail "findings do not mention 'imbalance'"
  fi

  if grep -qiE "recall" "${FINDINGS}"; then
    echo "OK:   findings mention recall"
  else
    fail "findings do not mention 'recall'"
  fi

  if grep -qiE "confusion" "${FINDINGS}"; then
    echo "OK:   findings mention the confusion matrix"
  else
    fail "findings do not mention 'confusion' matrix"
  fi

  if grep -qiE "class_weight|balanced|resampl|oversampl|undersampl|smote" "${FINDINGS}"; then
    echo "OK:   findings name a fix (class_weight/balanced/resample/SMOTE)"
  else
    fail "findings do not name a fix (class_weight/balanced/resampling/SMOTE)"
  fi
fi

# --- balanced training -------------------------------------------------------
if [ -f "${BALANCED}" ]; then
  echo "OK:   balanced_train.py exists"
else
  fail "balanced_train.py not found at ${BALANCED}"
fi

if [ -f "${BALANCED}" ]; then
  if [ -f "${WORKDIR}/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "${WORKDIR}/.venv/bin/activate"
  else
    fail "venv not found at ${WORKDIR}/.venv - run inject.sh first"
  fi

  OUT_FILE="$(mktemp)"
  if ( cd "${WORKDIR}" && python balanced_train.py ) > "${OUT_FILE}" 2>&1; then
    echo "OK:   balanced_train.py runs clean"

    # Prefer an explicit positive_class_recall line. Fall back to any recall
    # number if the student named it differently.
    REC_LINE="$(grep -iE 'positive_class_recall|positive.*recall|recall' "${OUT_FILE}" | tail -n 1 || true)"
    if [ -n "${REC_LINE}" ]; then
      REC="$(printf '%s\n' "${REC_LINE}" | grep -oE '[0-9]+\.[0-9]+' | tail -n 1 || true)"
      if [ -n "${REC}" ]; then
        if awk -v r="${REC}" 'BEGIN { exit !(r >= 0.40) }'; then
          echo "OK:   positive-class recall ${REC} is materially above the naive ~0.05"
        else
          fail "positive-class recall ${REC} is not materially above ~0.05 (need >= 0.40)"
        fi
      else
        fail "could not parse a recall number from balanced_train.py output"
      fi
    else
      fail "balanced_train.py printed no recall line - print positive-class recall"
    fi
  else
    echo "----- balanced_train.py output -----"
    cat "${OUT_FILE}"
    echo "------------------------------------"
    fail "balanced_train.py exited non-zero"
  fi
  rm -f "${OUT_FILE}"
fi

# --- verdict -----------------------------------------------------------------
if [ "${overall}" -eq "${PASS}" ]; then
  echo "RESULT: PASS - imbalance detected, corrected, and rare-class recall recovered"
  exit 0
else
  echo "RESULT: FAIL - see FAIL lines above"
  exit 1
fi
