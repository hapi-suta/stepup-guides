#!/usr/bin/env bash
#
# SURVIVE validator: region-outage
# PASS only if, with the PRIMARY region DOWN and the SECONDARY up, client.py
# runs cleanly and its RESULT was served by the SECONDARY cloud region
# (proving regional failover works). Local mocks only - no real cloud, no creds.
# Run on the lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-region-outage"
fail() {
  echo "FAIL: $1"
  pkill -f "region_server.py 8992" 2>/dev/null || true
  exit 1
}

[[ -f "${WORKDIR}/client.py" ]]        || fail "client.py not found. Run inject.sh first."
[[ -f "${WORKDIR}/region_server.py" ]] || fail "region_server.py not found. Run inject.sh first."

cd "${WORKDIR}"
echo "Ensuring PRIMARY (8991) is down and SECONDARY (8992) is up ..."
pkill -f "region_server.py 8991" 2>/dev/null || true
pkill -f "region_server.py 8992" 2>/dev/null || true
sleep 1
nohup python3 "${WORKDIR}/region_server.py" 8992 gcp-europe-west1 >/dev/null 2>&1 &
sleep 1

echo "Running your client.py with the primary region down ..."
if ! OUTPUT="$(python3 client.py 2>&1)"; then
  echo "${OUTPUT}"
  fail "client.py exited non-zero. It must catch the region outage and fail over."
fi

RESULT_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^RESULT ' | tail -n 1 || true)"
[[ -n "${RESULT_LINE}" ]] || { echo "${OUTPUT}"; fail "no RESULT line printed."; }
echo "RESULT line: ${RESULT_LINE}"

if printf '%s\n' "${RESULT_LINE}" | grep -q '"region": *"gcp-europe-west1"'; then
  echo "PASS: primary region was down and the client failed over to the secondary cloud region."
  pkill -f "region_server.py 8992" 2>/dev/null || true
  exit 0
else
  fail "RESULT did not come from the secondary region - failover is not working."
fi
