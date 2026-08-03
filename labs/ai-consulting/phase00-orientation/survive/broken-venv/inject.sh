#!/usr/bin/env bash
#
# SURVIVE scenario: broken-venv
# inject.sh - breaks the student's Python virtual environment setup.
#
# What this does (the "break"):
#   1. Creates a project virtual environment if one does not exist.
#   2. Installs a package (requests) into the SYSTEM Python (via pip --user),
#      NOT into the venv, so the student's project cannot find it while the
#      venv is active.
#   3. Corrupts the venv's interpreter symlink so `source activate` points at
#      a Python that no longer resolves - the classic "wrong interpreter".
#
# Safe to run on CentOS Stream 9 as ec2-user. Self-contained. Idempotent.

set -u

PROJECT_DIR="${HOME}/survive-venv-lab"
VENV_DIR="${PROJECT_DIR}/venv"

echo "[inject] Setting up broken-venv scenario in ${PROJECT_DIR}"

mkdir -p "${PROJECT_DIR}"
cd "${PROJECT_DIR}" || exit 1

# Pick a python to build the venv with.
PY=python3.12
command -v "${PY}" >/dev/null 2>&1 || PY=python3

# Create a fresh venv.
rm -rf "${VENV_DIR}"
"${PY}" -m venv "${VENV_DIR}"
echo "[inject] Created venv at ${VENV_DIR}"

# BREAK 1: install the project's package into the USER/system site, not the venv.
# The student will (wrongly) find it via system python but not inside the venv.
"${PY}" -m pip install --user --quiet requests 2>/dev/null || true
echo "[inject] Installed 'requests' into the SYSTEM python (--user), not the venv"

# BREAK 2: corrupt the venv interpreter symlink so it points nowhere valid.
if [ -e "${VENV_DIR}/bin/python" ]; then
    rm -f "${VENV_DIR}/bin/python" "${VENV_DIR}/bin/python3"
    ln -s /usr/bin/definitely-not-python "${VENV_DIR}/bin/python"
    ln -s /usr/bin/definitely-not-python "${VENV_DIR}/bin/python3"
    echo "[inject] Corrupted the venv python symlink (points to a missing interpreter)"
fi

echo
echo "[inject] DONE. The venv in ${VENV_DIR} is now broken."
echo "[inject] Your job: diagnose it, then recreate a working venv with 'requests'"
echo "[inject] installed INSIDE the venv (not the system python)."
echo "[inject] See runbook.md. Then run: bash validate.sh"
