#!/usr/bin/env bash
# Scenario 04 - Validate: Confirm cluster recovered from witness + primary failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-04-state.env"

header "Validate - Scenario 04: Witness Failure During Primary Crash"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. A primary exists and is reachable
NEW_PRIMARY=$(get_primary)
check "A primary is running" test -n "$NEW_PRIMARY"

# 3. New primary is not the original (failover occurred)
check "New primary ($NEW_PRIMARY) is not the crashed node ($ORIGINAL_PRIMARY)" \
  test "$NEW_PRIMARY" != "$ORIGINAL_PRIMARY"

# 4. Writes succeed
WRITE_OK=$(pg_exec "$NEW_PRIMARY" \
  "INSERT INTO employees(name, department) VALUES ('witness_validate','ops') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on primary" test -n "$WRITE_OK"

# 5. Data integrity
ROW_COUNT=$(pg_exec "$NEW_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "0")
check "Employee table has >= $PRE_CRASH_ROW_COUNT rows (found: $ROW_COUNT)" \
  test "$ROW_COUNT" -ge "$PRE_CRASH_ROW_COUNT"

# 6. Witness is back online
check "Witness ($NODE4) PostgreSQL is running" \
  remote_exec "$NODE4" "sudo -u postgres ${PG_BIN}/pg_isready -p ${PG_PORT}"

# 7. Witness repmgrd is running
check "Witness ($NODE4) repmgrd is running" \
  remote_exec "$NODE4" "systemctl is-active ${REPMGRD_SERVICE} 2>/dev/null || systemctl is-active repmgrd"

# 8. Old primary rejoined as standby
ORIG_RECOVERY=$(remote_exec "$ORIGINAL_PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null || echo "")
check "Original primary ($ORIGINAL_PRIMARY) is standby (in_recovery: $ORIG_RECOVERY)" \
  test "$ORIG_RECOVERY" = "t"

# 9. At least 2 standbys streaming
STREAMING_COUNT=$(pg_exec "$NEW_PRIMARY" \
  "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'" 2>/dev/null || echo "0")
check "At least 2 standbys streaming (found: $STREAMING_COUNT)" \
  test "$STREAMING_COUNT" -ge 2

# 10. repmgr cluster show has 4 nodes
CLUSTER_NODES=$(repmgr_exec "$NEW_PRIMARY" "cluster show --csv" 2>/dev/null | wc -l | tr -d ' ')
check "repmgr cluster has 4 nodes (found: $CLUSTER_NODES)" \
  test "$CLUSTER_NODES" -ge 4

# 11. repmgrd running on all data nodes
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  check "repmgrd running on $node_var ($node_ip)" \
    remote_exec "$node_ip" "systemctl is-active ${REPMGRD_SERVICE} 2>/dev/null || systemctl is-active repmgrd"
done

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
