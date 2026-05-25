#!/usr/bin/env bash
# Scenario 06 - Validate: Confirm repmgr metadata matches actual topology.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/stepup-repmgr-06-state.env"

header "Validate - Scenario 06: repmgr Metadata Desync"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# Helper to query repmgr database specifically
repmgr_db_exec() {
  local host="$1" sql="$2"
  remote_exec "$host" \
    "sudo -u postgres psql -p ${PG_PORT} -d repmgr -t -A -c \"${sql}\""
}

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. A primary exists
PRIMARY=$(get_primary)
check "A primary is running" test -n "$PRIMARY"

# 3. repmgr agrees on who the primary is
REPMGR_PRIMARY=$(get_repmgr_primary)
check "repmgr metadata agrees on primary (actual: $PRIMARY, repmgr: $REPMGR_PRIMARY)" \
  test "$PRIMARY" = "$REPMGR_PRIMARY"

# 4. repmgr shows the primary as type 'primary'
PRIMARY_TYPE=$(repmgr_db_exec "$PRIMARY" \
  "SELECT type FROM repmgr.nodes WHERE node_id=${PRIMARY_NODE_ID}" 2>/dev/null || echo "")
check "Node $PRIMARY_NODE_ID has type 'primary' in metadata (found: $PRIMARY_TYPE)" \
  test "$PRIMARY_TYPE" = "primary"

# 5. repmgr shows the standby as type 'standby'
STANDBY_TYPE=$(repmgr_db_exec "$PRIMARY" \
  "SELECT type FROM repmgr.nodes WHERE node_id=${STANDBY_NODE_ID}" 2>/dev/null || echo "")
check "Node $STANDBY_NODE_ID has type 'standby' in metadata (found: $STANDBY_TYPE)" \
  test "$STANDBY_TYPE" = "standby"

# 6. All nodes marked active in repmgr.nodes
ACTIVE_COUNT=$(repmgr_db_exec "$PRIMARY" \
  "SELECT count(*) FROM repmgr.nodes WHERE active = true" 2>/dev/null || echo "0")
check "All nodes active in repmgr.nodes (found: $ACTIVE_COUNT, expected: >= 4)" \
  test "$ACTIVE_COUNT" -ge 4

# 7. Writes succeed on primary
WRITE_OK=$(pg_exec "$PRIMARY" \
  "INSERT INTO employees(name, department) VALUES ('metadata_validate','engineering') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on primary ($PRIMARY)" test -n "$WRITE_OK"

# 8. Data integrity
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "0")
check "Employee table has >= $PRE_CORRUPT_ROW_COUNT rows (found: $ROW_COUNT)" \
  test "$ROW_COUNT" -ge "$PRE_CORRUPT_ROW_COUNT"

# 9. At least 2 standbys streaming
STREAMING_COUNT=$(pg_exec "$PRIMARY" \
  "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'" 2>/dev/null || echo "0")
check "At least 2 standbys streaming (found: $STREAMING_COUNT)" \
  test "$STREAMING_COUNT" -ge 2

# 10. repmgrd running on all nodes
for node_var in NODE1 NODE2 NODE3 NODE4; do
  node_ip="${!node_var}"
  check "repmgrd running on $node_var ($node_ip)" \
    remote_exec "$node_ip" "systemctl is-active ${REPMGRD_SERVICE} 2>/dev/null || systemctl is-active repmgrd"
done

# 11. repmgr cluster show has 4 nodes
CLUSTER_NODES=$(repmgr_exec "$PRIMARY" "cluster show --csv" 2>/dev/null | wc -l | tr -d ' ')
check "repmgr cluster has 4 nodes (found: $CLUSTER_NODES)" \
  test "$CLUSTER_NODES" -ge 4

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
