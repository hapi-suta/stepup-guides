#!/usr/bin/env bash
# Scenario 08 - Validate: Confirm split-brain resolved, single primary, data consistent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-08-state.env"

header "Validate - Scenario 08: Standby Promotion Race"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. Exactly ONE primary exists
PRIMARY_COUNT=0
FOUND_PRIMARY=""
for node in "$NODE1" "$NODE2" "$NODE3"; do
  RESULT=$(remote_exec "$node" \
    "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null || echo "t")
  RESULT=$(echo "$RESULT" | tr -d '[:space:]')
  if [[ "$RESULT" == "f" ]]; then
    (( PRIMARY_COUNT++ ))
    FOUND_PRIMARY="$node"
  fi
done
check "Exactly one primary exists (found: $PRIMARY_COUNT)" \
  test "$PRIMARY_COUNT" -eq 1

# 3. Primary is set
check "A primary was found" test -n "$FOUND_PRIMARY"

# 4. Writes succeed on the primary
WRITE_OK=$(pg_exec "$FOUND_PRIMARY" \
  "INSERT INTO employees(name, department) VALUES ('race_validate','SRE') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on primary ($FOUND_PRIMARY)" test -n "$WRITE_OK"

# 5. Data integrity
ROW_COUNT=$(pg_exec "$FOUND_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "0")
check "Employee table has >= $PRE_CRASH_ROW_COUNT rows (found: $ROW_COUNT)" \
  test "$ROW_COUNT" -ge "$PRE_CRASH_ROW_COUNT"

# 6. All 3 data nodes have PostgreSQL running
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  check "PostgreSQL running on $node_var ($node_ip)" \
    remote_exec "$node_ip" "sudo -u postgres ${PG_BIN}/pg_isready -p ${PG_PORT}"
done

# 7. Non-primary nodes are standbys
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  if [[ "$node_ip" == "$FOUND_PRIMARY" ]]; then continue; fi
  RECOVERY=$(remote_exec "$node_ip" \
    "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null || echo "")
  RECOVERY=$(echo "$RECOVERY" | tr -d '[:space:]')
  check "$node_var ($node_ip) is standby (in_recovery: $RECOVERY)" \
    test "$RECOVERY" = "t"
done

# 8. At least 2 standbys streaming
STREAMING_COUNT=$(pg_exec "$FOUND_PRIMARY" \
  "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'" 2>/dev/null || echo "0")
check "At least 2 standbys streaming (found: $STREAMING_COUNT)" \
  test "$STREAMING_COUNT" -ge 2

# 9. repmgrd running on all nodes
for node_var in NODE1 NODE2 NODE3 NODE4; do
  node_ip="${!node_var}"
  check "repmgrd running on $node_var ($node_ip)" \
    remote_exec "$node_ip" "systemctl is-active ${REPMGRD_SERVICE} 2>/dev/null || systemctl is-active repmgrd"
done

# 10. repmgr cluster show is clean
CLUSTER_NODES=$(repmgr_exec "$FOUND_PRIMARY" "cluster show --csv" 2>/dev/null | wc -l | tr -d ' ')
check "repmgr cluster has 4 nodes (found: $CLUSTER_NODES)" \
  test "$CLUSTER_NODES" -ge 4

# 11. Data consistent across all data nodes
P_COUNT=$(pg_exec "$FOUND_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  if [[ "$node_ip" == "$FOUND_PRIMARY" ]]; then continue; fi
  S_COUNT=$(pg_exec "$node_ip" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
  check "Data matches on $node_var (primary: $P_COUNT, node: $S_COUNT)" \
    test "$P_COUNT" = "$S_COUNT"
done

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
