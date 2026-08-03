#!/usr/bin/env bash
#
# SURVIVE scenario: git-disaster
# validate.sh - exits 0 when the secret is gone, 1 if not.
#
# Passing criteria:
#   1. The fake secret string is NOT present in any currently tracked file.
#   2. The fake secret string is NOT present anywhere in git history.
#
# Run this on your lab server as ec2-user, from anywhere.

LAB_DIR="${HOME}/survive-git-lab"
SECRET="sk-fake-1234567890ABCDEFsecretDONOTCOMMIT"

fail() {
    echo "[validate] FAIL: $1"
    exit 1
}

[ -d "${LAB_DIR}/.git" ] || fail "no git repo at ${LAB_DIR}. Run inject.sh first."

cd "${LAB_DIR}" || fail "cannot cd into ${LAB_DIR}"

# 1. Secret must not be in any tracked file.
if git grep -q "${SECRET}" 2>/dev/null; then
    fail "the secret is still in a tracked file. Remove it and untrack config.py (runbook steps 3 and 5)."
fi

# 2. Secret must not be anywhere in history.
HITS="$(git log --all --oneline -S "${SECRET}" 2>/dev/null)"
if [ -n "${HITS}" ]; then
    fail "the secret is still in git history. Scrub it with filter-branch (runbook step 6)."
fi

echo "[validate] PASS: no secret in tracked files and none found in git history"
exit 0
