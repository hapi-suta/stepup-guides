#!/usr/bin/env bash
###############################################################################
# Scenario 10: Automation Failure
# validate.sh - Verify Ansible connectivity and replication are restored
###############################################################################
# Pass criteria:
#   1. Ansible can ping all PG nodes from pg-ops
#   2. pg_hba.conf has no reject rules for replicator
#   3. Replication is streaming with acceptable lag
#   4. PostgreSQL is accepting connections
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../../config.sh"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${SSH_KEY}"

PASS=0
FAIL=0
TOTAL=4

echo "==========================================="
echo " VALIDATION: Automation Failure"
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

# ---- Check 1: Ansible can ping all nodes from pg-ops ----
echo "[1/4] Checking Ansible connectivity from pg-ops (${OPS_HOST})..."

ANSIBLE_RESULT=$(ssh ${SSH_OPTS} ${SSH_USER}@${OPS_HOST} \
  "cd ~/ansible && ansible all -i inventory/hosts.yml -m ping 2>&1" || echo "ANSIBLE_ERROR")

# Count successful pings
PING_SUCCESS=$(echo "${ANSIBLE_RESULT}" | grep -c "SUCCESS" || true)

EXPECTED_NODES=4
if [ "${PING_SUCCESS}" -ge "${EXPECTED_NODES}" ]; then
  check "Ansible can ping all PG nodes" 0 "${PING_SUCCESS}/${EXPECTED_NODES} node(s) responding with SUCCESS"
else
  check "Ansible can ping all PG nodes" 1 "Only ${PING_SUCCESS}/${EXPECTED_NODES} node(s) responding - check inventory IPs"
fi
echo ""

# ---- Check 2: pg_hba.conf allows replication from replica IP ----
echo "[2/4] Checking pg_hba.conf on pg-primary (${PRIMARY_HOST})..."

HBA_REJECT=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "sudo grep -c 'reject.*replicator\|replicator.*reject' /var/lib/pgsql/17/data/pg_hba.conf 2>/dev/null || echo '0'" 2>/dev/null)
HBA_REJECT=$(echo "${HBA_REJECT}" | tr -d '[:space:]')

if [ "${HBA_REJECT}" -eq 0 ] 2>/dev/null; then
  check "pg_hba.conf has no reject rules for replicator" 0 "No reject rules found"
else
  check "pg_hba.conf has no reject rules for replicator" 1 "Found ${HBA_REJECT} reject rule(s) for replicator - remove them and reload PG"
fi
echo ""

# ---- Check 3: Replication is streaming ----
echo "[3/4] Checking replication status on pg-primary (${PRIMARY_HOST})..."

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

# ---- Check 4: PostgreSQL is accepting connections ----
echo "[4/4] Checking PostgreSQL connectivity on pg-primary (${PRIMARY_HOST})..."

PG_OK=$(ssh ${SSH_OPTS} ${SSH_USER}@${PRIMARY_HOST} \
  "sudo -u postgres psql -d quantdb -t -A -c 'SELECT 1;'" 2>/dev/null || echo "error")

if [ "${PG_OK}" = "1" ]; then
  check "PostgreSQL is accepting connections" 0 "quantdb responds to queries"
else
  check "PostgreSQL is accepting connections" 1 "Could not connect to quantdb (got: ${PG_OK})"
fi
echo ""

# ---- Summary ----
echo "==========================================="
echo " RESULTS: ${PASS}/${TOTAL} checks passed"
echo "==========================================="
echo ""

if [ "${PASS}" -eq "${TOTAL}" ]; then
  echo " ALL CHECKS PASSED - Automation failure resolved!"
  echo ""
  exit 0
else
  echo " ${FAIL} check(s) failed - issues remain."
  echo " Review the failures above and re-run this script."
  echo ""
  exit 1
fi
