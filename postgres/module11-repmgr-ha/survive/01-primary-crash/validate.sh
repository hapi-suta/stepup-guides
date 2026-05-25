#!/usr/bin/env bash
# Scenario 01 - Validate: Confirm auto-failover completed and old primary rejoined.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-01-state.env"

header "Validate - Scenario 01: Primary Crash (repmgr auto-failover)"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. A node is now primary
NEW_PRIMARY=$(get_primary)
check "A node is running as primary" test -n "$NEW_PRIMARY"

# 3. The new primary is NOT the original primary (failover happened)
check "New primary ($NEW_PRIMARY) is not the crashed node ($ORIGINAL_PRIMARY)" \
  test "$NEW_PRIMARY" != "$ORIGINAL_PRIMARY"

# 4. Writes succeed on the new primary
WRITE_OK=$(pg_exec "$NEW_PRIMARY" \
  "INSERT INTO employees(name, department) VALUES ('chaos_validate','SRE') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on new primary" test -n "$WRITE_OK"

# 5. Employee data is intact (>= 10000 rows)
ROW_COUNT=$(pg_exec "$NEW_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "0")
check "Employee table has >= 10000 rows (found: $ROW_COUNT)" \
  test "$ROW_COUNT" -ge 10000

# 6. Timeline advanced after promotion
NEW_TL=$(pg_exec "$NEW_PRIMARY" \
  "SELECT timeline_id FROM pg_control_checkpoint()" 2>/dev/null || echo "0")
check "Timeline advanced (current: $NEW_TL, was: $PRE_CRASH_TIMELINE)" \
  test "$NEW_TL" -gt "$PRE_CRASH_TIMELINE"

# 7. Original primary is back and running as standby
ORIG_RECOVERY=$(remote_exec "$ORIGINAL_PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null || echo "")
check "Original primary ($ORIGINAL_PRIMARY) rejoined as standby (in_recovery: $ORIG_RECOVERY)" \
  test "$ORIG_RECOVERY" = "t"

# 8. At least 2 standbys streaming from new primary
STREAMING_COUNT=$(pg_exec "$NEW_PRIMARY" \
  "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'" 2>/dev/null || echo "0")
check "At least 2 standbys streaming (found: $STREAMING_COUNT)" \
  test "$STREAMING_COUNT" -ge 2

# 9. repmgrd running on all data nodes
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  check "repmgrd running on $node_var ($node_ip)" \
    remote_exec "$node_ip" "systemctl is-active ${REPMGRD_SERVICE} 2>/dev/null || systemctl is-active repmgrd"
done

# 10. repmgr cluster show has correct node count
CLUSTER_NODES=$(repmgr_exec "$NEW_PRIMARY" "cluster show --csv" 2>/dev/null | wc -l | tr -d ' ')
check "repmgr cluster has 4 nodes (found: $CLUSTER_NODES)" \
  test "$CLUSTER_NODES" -ge 4

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
