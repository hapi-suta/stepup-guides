#!/usr/bin/env bash
# Automated verification that the streaming replication build is complete.
# Run from the lab root: ./build/verify.sh
#
# Sources student.env for NODE1/NODE2 IPs. Exits 0 if all checks pass.

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

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
[[ -n "${SSH_KEY:-}" ]] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
PG_USER="${PG_USER:-postgres}"
SSH_USER="${SSH_USER:-root}"

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
echo "VERIFYING: streaming-replication build"
echo "  Primary (NODE1): $NODE1"
echo "  Standby (NODE2): $NODE2"
echo "=============================================================="

# 1. SSH reachability
ssh $SSH_OPTS "$SSH_USER@$NODE1" "echo ok" >/dev/null 2>&1
check "SSH to primary ($NODE1)" "$?"

ssh $SSH_OPTS "$SSH_USER@$NODE2" "echo ok" >/dev/null 2>&1
check "SSH to standby ($NODE2)" "$?"

# 2. PostgreSQL running on both
ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc 'SELECT 1;'" >/dev/null 2>&1
check "PostgreSQL running on primary" "$?"

ssh $SSH_OPTS "$SSH_USER@$NODE2" "sudo -iu postgres psql -tAc 'SELECT 1;'" >/dev/null 2>&1
check "PostgreSQL running on standby" "$?"

# 3. wal_level = replica on primary
WAL_LEVEL=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc 'SHOW wal_level;'" 2>/dev/null | tr -d ' ')
[[ "$WAL_LEVEL" == "replica" ]]
check "wal_level = replica on primary (got: $WAL_LEVEL)" "$?"

# 4. archive_mode = on
ARCHIVE=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc 'SHOW archive_mode;'" 2>/dev/null | tr -d ' ')
[[ "$ARCHIVE" == "on" ]]
check "archive_mode = on (got: $ARCHIVE)" "$?"

# 4b. wal_log_hints = on
WAL_HINTS=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc 'SHOW wal_log_hints;'" 2>/dev/null | tr -d ' ')
[[ "$WAL_HINTS" == "on" ]]
check "wal_log_hints = on (got: $WAL_HINTS)" "$?"

# 5. Replicator role exists
REPL_ROLE=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc \"SELECT rolreplication FROM pg_roles WHERE rolname='replicator';\"" 2>/dev/null | tr -d ' ')
[[ "$REPL_ROLE" == "t" ]]
check "replicator role exists with REPLICATION privilege" "$?"

# 6. Replication slot exists
SLOT=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc \"SELECT slot_name FROM pg_replication_slots WHERE slot_name='standby_slot';\"" 2>/dev/null | tr -d ' ')
[[ "$SLOT" == "standby_slot" ]]
check "replication slot 'standby_slot' exists" "$?"

# 7. Standby is in recovery
IN_RECOVERY=$(ssh $SSH_OPTS "$SSH_USER@$NODE2" "sudo -iu postgres psql -tAc 'SELECT pg_is_in_recovery();'" 2>/dev/null | tr -d ' ')
[[ "$IN_RECOVERY" == "t" ]]
check "standby is in recovery mode" "$?"

# 8. Replication is streaming
REPL_STATE=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -tAc \"SELECT state FROM pg_stat_replication LIMIT 1;\"" 2>/dev/null | tr -d ' ')
[[ "$REPL_STATE" == "streaming" ]]
check "replication state = streaming (got: $REPL_STATE)" "$?"

# 9. Data exists and matches
PRIMARY_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -d labdb -tAc 'SELECT count(*) FROM employees;'" 2>/dev/null | tr -d ' ')
STANDBY_COUNT=$(ssh $SSH_OPTS "$SSH_USER@$NODE2" "sudo -iu postgres psql -d labdb -tAc 'SELECT count(*) FROM employees;'" 2>/dev/null | tr -d ' ')
[[ "$PRIMARY_COUNT" == "$STANDBY_COUNT" && "$PRIMARY_COUNT" -ge 10000 ]]
check "data matches: primary=$PRIMARY_COUNT, standby=$STANDBY_COUNT" "$?"

# 10. Live replication test
PROBE="verify_$(date +%s)"
ssh $SSH_OPTS "$SSH_USER@$NODE1" "sudo -iu postgres psql -d labdb -c \"INSERT INTO employees (name, department) VALUES ('$PROBE', 'verify');\"" >/dev/null 2>&1
sleep 2
FOUND=$(ssh $SSH_OPTS "$SSH_USER@$NODE2" "sudo -iu postgres psql -d labdb -tAc \"SELECT count(*) FROM employees WHERE name='$PROBE';\"" 2>/dev/null | tr -d ' ')
[[ "$FOUND" == "1" ]]
check "live replication: probe row appeared on standby" "$?"

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
echo "BUILD COMPLETE. Your streaming replication cluster is ready."
echo "Proceed to use/01-check-replication-status.md for Phase 2."
exit 0
