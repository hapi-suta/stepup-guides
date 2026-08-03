#!/usr/bin/env bash
#
# SURVIVE validator: cost-blowout
#
# PASS only if the spender:
#   1. exists and runs cleanly (exit 0)
#   2. prints a SPEND line showing the budget STOPPED the run
#      (stopped_by_budget=true) with cost at or under the budget cap
#
# The budget cap the validator expects is BUDGET_USD below. Your fix must stop
# spending once cost reaches (or would exceed) that cap. Caching is encouraged
# and makes staying under the cap easy, but the budget stop is what is graded.
#
# Everything runs against a LOCAL mock server - no real API, no key.
# Run on the lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-cost-blowout"
VENV="${VENV:-${WORKDIR}/venv}"
SPENDER="${WORKDIR}/spender.py"
BUDGET_USD="0.50"   # the spender must not exceed this; it must stop at/under it

fail() {
  echo "FAIL: $1"
  exit 1
}

# --- check 1: files exist ---------------------------------------------------
[[ -f "${SPENDER}" ]] || fail "${SPENDER} not found. Run inject.sh first, then add cost controls."
[[ -f "${WORKDIR}/mock_server.py" ]] || fail "mock_server.py not found. Run inject.sh first."

# --- venv -------------------------------------------------------------------
if [[ ! -d "${VENV}" ]]; then
  echo "venv missing, creating it ..."
  python3.12 -m venv "${VENV}"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"

# --- ensure the mock server is up -------------------------------------------
if ! curl -s -X POST "http://127.0.0.1:8973/" -d '{"prompt":"ping"}' >/dev/null 2>&1; then
  echo "Mock server not responding on 8973, starting it ..."
  pkill -f "mock_server.py 8973" 2>/dev/null || true
  sleep 1
  nohup python "${WORKDIR}/mock_server.py" 8973 >/dev/null 2>&1 &
  sleep 1
fi

# --- check 2: spender runs cleanly and prints a SPEND line ------------------
echo "Running your spender.py ..."
OUTPUT=""
if ! OUTPUT="$(cd "${WORKDIR}" && python spender.py 2>&1)"; then
  echo "${OUTPUT}"
  fail "spender.py exited non-zero."
fi

SPEND_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^SPEND ' | tail -n 1 || true)"
if [[ -z "${SPEND_LINE}" ]]; then
  echo "${OUTPUT}"
  fail "no SPEND line printed. spender.py must print 'SPEND calls=.. cost_usd=.. stopped_by_budget=..'."
fi
echo "SPEND line: ${SPEND_LINE}"

# --- check 3: budget actually stopped the run -------------------------------
if ! printf '%s\n' "${SPEND_LINE}" | grep -q 'stopped_by_budget=true'; then
  fail "budget did not stop the run (stopped_by_budget is not true). Add a budget cap that halts spending."
fi

# --- check 4: cost is at or under the budget cap ----------------------------
COST="$(printf '%s\n' "${SPEND_LINE}" | sed -n 's/.*cost_usd=\([0-9.]*\).*/\1/p')"
[[ -n "${COST}" ]] || fail "could not read cost_usd from the SPEND line."

UNDER="$(python - "${COST}" "${BUDGET_USD}" <<'PYEOF'
import sys
cost = float(sys.argv[1]); budget = float(sys.argv[2])
print("yes" if cost <= budget + 1e-9 else "no")
PYEOF
)"

if [[ "${UNDER}" != "yes" ]]; then
  fail "cost_usd ${COST} exceeded the budget cap ${BUDGET_USD}. The budget must stop spending before it is exceeded."
fi

echo "PASS: the budget stopped the run (cost ${COST} USD, within the ${BUDGET_USD} USD cap)."
exit 0
