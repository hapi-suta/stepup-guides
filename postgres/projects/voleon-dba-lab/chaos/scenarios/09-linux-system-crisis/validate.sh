#!/usr/bin/env bash
###############################################################################
# Scenario 09: Linux System Crisis
# validate.sh - Verify all three injected issues are resolved
###############################################################################
# Pass criteria:
#   1. /tmp chaos fill file is removed
#   2. vm.swappiness is 10 or less
#   3. No iptables DROP rules for replica traffic
#   4. PostgreSQL is running and accepting connections
#   5. Replication is streaming with acceptable lag
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_KEY}"

PASS=0
FAIL=0
TOTAL=5

echo "==========================================="
echo " VALIDATION: Linux System Crisis"
echo "==========================================="
echo ""

# Helper function
check() {
  local description="$1"
  local result="$2"  # 0 = pass, non-zero = fail
  local detail="$3"

  if [ "$result" -eq 0 ]; then
    echo "  [PASS] ${description}"
    [ -n "$detail" ] && echo "         ${detail}"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] ${description}"
    [ -n "$detail" ] && echo "         ${detail}"
    FAIL=$((FAIL + 1))
  fi
}

# ---- Check 1: /tmp chaos fill file is removed ----
echo "[1/5] Checking /tmp chaos file on pg-primary (${PRIMARY_HOST})..."

TMP_CHAOS=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "[ -f /tmp/.chaos_tmpfill ] && echo 'exists' || echo 'clean'" 2>/dev/null || echo "unknown")
TMP_CHAOS=$(echo "${TMP_CHAOS}" | tr -d '[:space:]')

if [ "${TMP_CHAOS}" = "clean" ]; then
  TMP_PCT=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} "df /tmp --output=pcent | tail -1 | tr -d ' %'" 2>/dev/null)
  check "/tmp chaos fill file removed" 0 "Current /tmp usage: ${TMP_PCT}%"
else
  check "/tmp chaos fill file removed" 1 "/tmp/.chaos_tmpfill still exists - remove it"
fi
echo ""

# ---- Check 2: vm.swappiness is low (10 or less) ----
echo "[2/5] Checking vm.swappiness on pg-primary (${PRIMARY_HOST})..."

SWAPPINESS=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "cat /proc/sys/vm/swappiness" 2>/dev/null || echo "999")

if [ "${SWAPPINESS}" -le 10 ] 2>/dev/null; then
  check "vm.swappiness is 10 or less" 0 "Current value: ${SWAPPINESS}"
else
  check "vm.swappiness is 10 or less" 1 "Current value: ${SWAPPINESS} (should be 1-10)"
fi
echo ""

# ---- Check 3: No iptables DROP rules for replica traffic ----
echo "[3/5] Checking iptables OUTPUT rules on pg-primary (${PRIMARY_HOST})..."

DROP_COUNT=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "sudo iptables -L OUTPUT -n 2>/dev/null | grep 'DROP.*statistic' | grep -c '${REPLICA_PRIVATE}' || true" 2>/dev/null)
DROP_COUNT=$(echo "${DROP_COUNT}" | tr -d '[:space:]')
[ -z "${DROP_COUNT}" ] && DROP_COUNT=0

if [ "${DROP_COUNT}" -eq 0 ] 2>/dev/null; then
  check "No iptables DROP rules for replica traffic" 0 "No packet-drop rules found"
else
  check "No iptables DROP rules for replica traffic" 1 "Found ${DROP_COUNT} DROP rule(s) targeting ${REPLICA_PRIVATE}"
fi
echo ""

# ---- Check 4: PostgreSQL is running and accepting connections ----
echo "[4/5] Checking PostgreSQL connectivity on pg-primary (${PRIMARY_HOST})..."

PG_OK=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "sudo -u postgres psql -d quantdb -t -A -c 'SELECT 1;'" 2>/dev/null || echo "error")

if [ "${PG_OK}" = "1" ]; then
  check "PostgreSQL is running and accepting connections" 0 "quantdb responds to queries"
else
  check "PostgreSQL is running and accepting connections" 1 "Could not connect to quantdb (got: ${PG_OK})"
fi
echo ""

# ---- Check 5: Replication is streaming with near-zero lag ----
echo "[5/5] Checking replication status on pg-primary (${PRIMARY_HOST})..."

REPL_STATE=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "sudo -u postgres psql -d quantdb -t -A -c \"SELECT state FROM pg_stat_replication WHERE client_addr = '${REPLICA_PRIVATE}' LIMIT 1;\"" 2>/dev/null || echo "unknown")

REPL_LAG_SECS=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "sudo -u postgres psql -d quantdb -t -A -c \"SELECT COALESCE(EXTRACT(EPOCH FROM replay_lag)::int, -1) FROM pg_stat_replication WHERE client_addr = '${REPLICA_PRIVATE}' LIMIT 1;\"" 2>/dev/null || echo "-1")

# Trim whitespace
REPL_STATE=$(echo "${REPL_STATE}" | tr -d '[:space:]')
REPL_LAG_SECS=$(echo "${REPL_LAG_SECS}" | tr -d '[:space:]')

if [ "${REPL_STATE}" = "streaming" ] && [ "${REPL_LAG_SECS}" -le 5 ] 2>/dev/null; then
  check "Replication is streaming with acceptable lag" 0 "State: ${REPL_STATE}, Lag: ${REPL_LAG_SECS}s"
elif [ "${REPL_STATE}" = "streaming" ]; then
  check "Replication is streaming with acceptable lag" 1 "State: ${REPL_STATE}, but lag is ${REPL_LAG_SECS}s (should be < 5s)"
else
  check "Replication is streaming with acceptable lag" 1 "State: '${REPL_STATE}' (expected 'streaming'), Lag: ${REPL_LAG_SECS}s"
fi
echo ""

# ---- Summary ----
echo "==========================================="
echo " RESULTS: ${PASS}/${TOTAL} checks passed"
echo "==========================================="
echo ""

if [ "${PASS}" -eq "${TOTAL}" ]; then
  echo " ALL CHECKS PASSED - System crisis resolved!"
  echo ""
  exit 0
else
  echo " ${FAIL} check(s) failed - issues remain."
  echo " Review the failures above and re-run this script."
  echo ""
  exit 1
fi
