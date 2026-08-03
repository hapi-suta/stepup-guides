#!/usr/bin/env bash
#
# SURVIVE validator: provider-outage
#
# PASS only if the client:
#   1. exists and runs cleanly (exit 0) with the PRIMARY provider DOWN
#   2. prints a RESULT line whose JSON shows it was served by the SECONDARY
#      (backup) provider - proving graceful degradation / fallback works
#
# Everything runs against LOCAL mock servers - no real API, no key.
# Run on the lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-provider-outage"
VENV="${WORKDIR}/venv"
CLIENT="${WORKDIR}/client.py"

fail() {
  echo "FAIL: $1"
  # best-effort cleanup of the backup server we start below
  pkill -f "mock_server.py 8972" 2>/dev/null || true
  exit 1
}

# --- check 1: files exist ---------------------------------------------------
[[ -f "${CLIENT}" ]] || fail "${CLIENT} not found. Run inject.sh first, then add fallback."
[[ -f "${WORKDIR}/mock_server.py" ]] || fail "mock_server.py not found. Run inject.sh first."

# --- venv -------------------------------------------------------------------
if [[ ! -d "${VENV}" ]]; then
  echo "venv missing, creating it ..."
  python3.12 -m venv "${VENV}"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"

# --- ensure the PRIMARY is DOWN and the SECONDARY is UP ---------------------
echo "Ensuring PRIMARY (8971) is down and SECONDARY (8972) is up ..."
pkill -f "mock_server.py 8971" 2>/dev/null || true   # primary must stay down
pkill -f "mock_server.py 8972" 2>/dev/null || true
sleep 1
nohup python "${WORKDIR}/mock_server.py" 8972 secondary >/dev/null 2>&1 &
sleep 1

# --- check 2: client runs cleanly and prints a RESULT -----------------------
echo "Running your client.py with the primary provider down ..."
OUTPUT=""
if ! OUTPUT="$(cd "${WORKDIR}" && python client.py 2>&1)"; then
  echo "${OUTPUT}"
  pkill -f "mock_server.py 8972" 2>/dev/null || true
  fail "client.py exited non-zero. It must catch the primary failure and fall back."
fi

RESULT_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^RESULT ' | tail -n 1 || true)"
if [[ -z "${RESULT_LINE}" ]]; then
  echo "${OUTPUT}"
  pkill -f "mock_server.py 8972" 2>/dev/null || true
  fail "no RESULT line printed. client.py must print 'RESULT <json>' after succeeding."
fi

# --- check 3: served by the SECONDARY (fallback actually happened) ----------
echo "RESULT line: ${RESULT_LINE}"
if printf '%s\n' "${RESULT_LINE}" | grep -q '"provider": *"secondary"'; then
  echo "PASS: primary was down, and the client degraded gracefully to the secondary provider."
  pkill -f "mock_server.py 8972" 2>/dev/null || true
  exit 0
else
  pkill -f "mock_server.py 8972" 2>/dev/null || true
  fail "RESULT did not come from the secondary provider - fallback is not working. It must serve from 'secondary' when the primary is down."
fi
