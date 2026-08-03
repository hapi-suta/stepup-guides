#!/usr/bin/env bash
#
# SURVIVE validator: rate-limit-429-storm
#
# PASS only if the client:
#   1. exists and runs cleanly (exit 0) against the rate-limiting mock server
#   2. prints a DONE line showing ALL requests eventually succeeded
#      (succeeded == total), proving backoff + batching survived the 429 storm
#
# Everything runs against a LOCAL mock server that enforces a fake rate limit -
# no real API, no key.
# Run on the lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-rate-limit-429-storm"
VENV="${VENV:-${WORKDIR}/venv}"
CLIENT="${WORKDIR}/client.py"

fail() {
  echo "FAIL: $1"
  exit 1
}

# --- check 1: files exist ---------------------------------------------------
[[ -f "${CLIENT}" ]] || fail "${CLIENT} not found. Run inject.sh first, then add backoff + batching."
[[ -f "${WORKDIR}/mock_server.py" ]] || fail "mock_server.py not found. Run inject.sh first."

# --- venv -------------------------------------------------------------------
if [[ ! -d "${VENV}" ]]; then
  echo "venv missing, creating it ..."
  python3.12 -m venv "${VENV}"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"

# --- ensure the rate-limiting mock server is up -----------------------------
if ! curl -s -X POST "http://127.0.0.1:8974/" -d '{"prompt":"ping"}' >/dev/null 2>&1; then
  echo "Mock server not responding on 8974, starting it ..."
  pkill -f "mock_server.py 8974" 2>/dev/null || true
  sleep 1
  nohup python "${WORKDIR}/mock_server.py" 8974 >/dev/null 2>&1 &
  sleep 1
fi

# --- check 2: client runs cleanly and prints a DONE line --------------------
echo "Running your client.py against the rate-limiting server ..."
OUTPUT=""
if ! OUTPUT="$(cd "${WORKDIR}" && python client.py 2>&1)"; then
  echo "${OUTPUT}"
  fail "client.py exited non-zero. It must survive 429s with backoff, not crash."
fi

DONE_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^DONE ' | tail -n 1 || true)"
if [[ -z "${DONE_LINE}" ]]; then
  echo "${OUTPUT}"
  fail "no DONE line printed. client.py must print 'DONE succeeded=.. total=..'."
fi
echo "DONE line: ${DONE_LINE}"

# --- check 3: ALL requests eventually succeeded -----------------------------
SUCCEEDED="$(printf '%s\n' "${DONE_LINE}" | sed -n 's/.*succeeded=\([0-9]*\).*/\1/p')"
TOTAL="$(printf '%s\n' "${DONE_LINE}" | sed -n 's/.*total=\([0-9]*\).*/\1/p')"
[[ -n "${SUCCEEDED}" && -n "${TOTAL}" ]] || fail "could not read succeeded/total from the DONE line."

if [[ "${SUCCEEDED}" -eq "${TOTAL}" && "${TOTAL}" -gt 0 ]]; then
  echo "PASS: survived the 429 storm - all ${TOTAL} requests eventually succeeded via backoff + batching."
  exit 0
else
  fail "only ${SUCCEEDED}/${TOTAL} requests succeeded. Backoff + batching must let ALL requests through eventually."
fi
