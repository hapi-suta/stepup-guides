#!/usr/bin/env bash
#
# SURVIVE scenario: broken-venv
# validate.sh - exits 0 when the environment is fixed, 1 if not.
#
# Passing criteria:
#   1. A venv is active (VIRTUAL_ENV set) OR the project venv exists and works.
#   2. The 'requests' package loads from INSIDE the venv, not the system python.
#
# Run this on your lab server as ec2-user, ideally with the venv active.

PROJECT_DIR="${HOME}/survive-venv-lab"
VENV_DIR="${PROJECT_DIR}/venv"
VENV_PY="${VENV_DIR}/bin/python"

fail() {
    echo "[validate] FAIL: $1"
    exit 1
}

# 1. The venv must exist and have a working interpreter.
if [ ! -x "${VENV_PY}" ]; then
    fail "no working python at ${VENV_PY}. Recreate the venv (runbook step 7)."
fi

if ! "${VENV_PY}" --version >/dev/null 2>&1; then
    fail "the venv python is broken. Delete and recreate the venv (runbook steps 6-7)."
fi

# 2. requests must import AND load from inside the venv directory.
PKG_PATH="$("${VENV_PY}" -c "import requests; print(requests.__file__)" 2>/dev/null)"
if [ -z "${PKG_PATH}" ]; then
    fail "'requests' does not import in the venv. Activate the venv and 'pip install requests' (runbook step 9)."
fi

case "${PKG_PATH}" in
    "${VENV_DIR}"/*)
        : # good - loaded from inside the venv
        ;;
    *)
        fail "'requests' loads from ${PKG_PATH}, which is OUTSIDE the venv. Install it inside the venv (runbook step 9)."
        ;;
esac

echo "[validate] PASS: venv is active and 'requests' loads from inside the venv"
exit 0
