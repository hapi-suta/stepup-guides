#!/usr/bin/env bash
# Automated verification that the repmgr-ha build (CentOS Stream 9) is complete.
# Run from the lab root: ./build-centos/verify.sh
#
# Sources student.env for NODE1/NODE2/NODE3/NODE4 IPs. Exits 0 if all checks pass.

set -uo pipefail

# Find student.env - check lab root, then labs root
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$SCRIPT_DIR/student.env" ]]; then
  source "$SCRIPT_DIR/student.env"
elif [[ -f "$SCRIPT_DIR/../../../student.env" ]]; then
  source "$SCRIPT_DIR/../../../student.env"
else
  echo "ERROR: No student.env found. Copy student.env.example and fill in your IPs." >&2
  exit 2
fi

[[ -z "${NODE1:-}" ]] && { echo "ERROR: NODE1 not set in student.env"; exit 2; }
[[ -z "${NODE2:-}" ]] && { echo "ERROR: NODE2 not set in student.env"; exit 2; }
[[ -z "${NODE3:-}" ]] && { echo "ERROR: NODE3 not set in student.env"; exit 2; }
[[ -z "${NODE4:-}" ]] && { echo "ERROR: NODE4 not set in student.env"; exit 2; }

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
PG_USER="${PG_USER:-postgres}"
SSH_USER="${SSH_USER:-ec2-user}"
REPMGR_CONF="/etc/repmgr/16/repmgr.conf"
PG_SERVICE="postgresql-16"

PASS=0
FAIL=0

check() {
  local label="$1"
  local rc="$2"
  if [[ "$rc" == "0" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

echo "=============================================================="
echo "VERIFYING: repmgr-ha build (CentOS Stream 9)"
echo "  Primary   (NODE1): $NODE1"
echo "  Standby 1 (NODE2): $NODE2"
echo "  Standby 2 (NODE3): $NODE3"
echo "  Witness   (NODE4): $NODE4"
echo "=============================================================="

# 1. SSH reachability to all 4 nodes
for node_var in NODE1 NODE2 NODE3 NODE4; do
  node_ip="${!node_var}"
  ssh $SSH_OPTS "$SSH_USER@$node_ip" "echo ok" >/dev/null 2>&1
  check "SSH to $node_var ($node_ip)" "$?"
done

# 2. PostgreSQL running on all 4 nodes
for node_var in NODE1 NODE2 NODE3 NODE4; do
  node_ip="${!node_var}"
  ssh $SSH_OPTS "$SSH_USER@$node_ip" "sudo -iu postgres psql -tAc 'SELECT 1;'" >/dev/null 2>&1
  check "PostgreSQL running on $node_var ($node_ip)" "$?"
done

# 3. repmgr installed on all nodes
for node_var in NODE1 NODE2 NODE3 NODE4; do
  node_ip="${!node_var}"
  ssh $SSH_OPTS "$SSH_USER@$node_ip" "/usr/pgsql-16/bin/repmgr --version" >/dev/null 2>&1
  check "repmgr installed on $node_var ($node_ip)" "$?"
done

# 4. NODE1 is primary (not in recovery)
IN_RECOVERY=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc 'SELECT pg_is_in_recovery();'" 2>/dev/null | tr -d ' ')
[[ "$IN_RECOVERY" == "f" ]]
check "NODE1 is primary (pg_is_in_recovery = f)" "$?"

# 5. NODE2 is in recovery
IN_RECOVERY=$(ssh $SSH_OPTS "$SSH_USER@$NODE2" "sudo -iu postgres psql -tAc 'SELECT pg_is_in_recovery();'" 2>/dev/null | tr -d ' ')
[[ "$IN_RECOVERY" == "t" ]]
check "NODE2 is standby (pg_is_in_recovery = t)" "$?"

# 6. NODE3 is in recovery
IN_RECOVERY=$(ssh $SSH_OPTS "$SSH_USER@$NODE3" "sudo -iu postgres psql -tAc 'SELECT pg_is_in_recovery();'" 2>/dev/null | tr -d ' ')
[[ "$IN_RECOVERY" == "t" ]]
check "NODE3 is standby (pg_is_in_recovery = t)" "$?"

# 7. repmgr cluster show has 4 nodes
NODE_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres /usr/pgsql-16/bin/repmgr -f $REPMGR_CONF cluster show --csv 2>/dev/null | wc -l" 2>/dev/null | tr -d ' ')
[[ "$NODE_COUNT" -ge 4 ]]
check "repmgr cluster show has >= 4 nodes (found: $NODE_COUNT)" "$?"

# 8. Replication streaming from at least 2 standbys
REPL_STATE=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc \"SELECT count(*) FROM pg_stat_replication WHERE state='streaming';\"" 2>/dev/null | tr -d ' ')
[[ "$REPL_STATE" -ge 2 ]]
check "At least 2 standbys streaming (found: $REPL_STATE)" "$?"

# 9. Witness registered (node_id=4 in repmgr.nodes)
WITNESS=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -d repmgr -tAc \"SELECT type FROM repmgr.nodes WHERE node_id=4;\"" 2>/dev/null | tr -d ' ')
[[ "$WITNESS" == "witness" ]]
check "Witness registered (node_id=4, type=$WITNESS)" "$?"

# 10. repmgrd running on all nodes
for node_var in NODE1 NODE2 NODE3 NODE4; do
  node_ip="${!node_var}"
  ssh $SSH_OPTS "$SSH_USER@$node_ip" "systemctl is-active repmgr-16" >/dev/null 2>&1
  check "repmgrd running on $node_var ($node_ip)" "$?"
done

# 11. Replication slots exist
SLOT_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc \"SELECT count(*) FROM pg_replication_slots;\"" 2>/dev/null | tr -d ' ')
[[ "$SLOT_COUNT" -ge 2 ]]
check "Replication slots on primary (found: $SLOT_COUNT, need >= 2)" "$?"

# 12. Data matches across primary and standbys
PRIMARY_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -d labdb -tAc 'SELECT count(*) FROM employees;'" 2>/dev/null | tr -d ' ')
STANDBY2_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE2" "sudo -iu postgres psql -d labdb -tAc 'SELECT count(*) FROM employees;'" 2>/dev/null | tr -d ' ')
STANDBY3_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE3" "sudo -iu postgres psql -d labdb -tAc 'SELECT count(*) FROM employees;'" 2>/dev/null | tr -d ' ')
[[ "$PRIMARY_COUNT" == "$STANDBY2_COUNT" && "$PRIMARY_COUNT" == "$STANDBY3_COUNT" && "$PRIMARY_COUNT" -ge 10000 ]]
check "Data matches: primary=$PRIMARY_COUNT, standby2=$STANDBY2_COUNT, standby3=$STANDBY3_COUNT" "$?"

# 13. Live replication test
PROBE="verify_$(date +%s)"
ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -d labdb -c \"INSERT INTO employees (name, department) VALUES ('$PROBE', 'verify');\"" >/dev/null 2>&1
sleep 2
FOUND2=$(ssh $SSH_OPTS "$SSH_USER@$NODE2" "sudo -iu postgres psql -d labdb -tAc \"SELECT count(*) FROM employees WHERE name='$PROBE';\"" 2>/dev/null | tr -d ' ')
FOUND3=$(ssh $SSH_OPTS "$SSH_USER@$NODE3" "sudo -iu postgres psql -d labdb -tAc \"SELECT count(*) FROM employees WHERE name='$PROBE';\"" 2>/dev/null | tr -d ' ')
[[ "$FOUND2" == "1" && "$FOUND3" == "1" ]]
check "Live replication: probe row appeared on both standbys" "$?"

# 14. wal_log_hints is on
WAL_HINTS=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc 'SHOW wal_log_hints;'" 2>/dev/null | tr -d ' ')
[[ "$WAL_HINTS" == "on" ]]
check "wal_log_hints = on (got: $WAL_HINTS)" "$?"

echo ""
echo "=============================================================="
echo "SUMMARY: $PASS passed, $FAIL failed"
echo "=============================================================="

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Fix the failing checks, then re-run this script."
  echo "Do not proceed to Phase 2 until all checks pass."
  exit 1
fi

echo ""
echo "BUILD COMPLETE. Your repmgr HA cluster is ready."
echo "Proceed to use/01-check-cluster-status.md for Phase 2."
exit 0
