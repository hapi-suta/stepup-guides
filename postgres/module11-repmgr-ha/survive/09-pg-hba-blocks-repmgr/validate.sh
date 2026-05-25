#!/usr/bin/env bash
# Scenario 09 - Validate: Confirm pg_hba is fixed and replication restored.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/stepup-repmgr-09-state.env"

header "Validate - Scenario 09: pg_hba Blocks repmgr"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. A primary exists
NEW_PRIMARY=$(get_primary)
check "A primary is running" test -n "$NEW_PRIMARY"

# 3. Writes succeed on the new primary
WRITE_OK=$(pg_exec "$NEW_PRIMARY" \
  "INSERT INTO employees(name, department) VALUES ('hba_validate','SRE') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on primary ($NEW_PRIMARY)" test -n "$WRITE_OK"

# 4. Data integrity
ROW_COUNT=$(pg_exec "$NEW_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "0")
check "Employee table has >= $PRE_CRASH_ROW_COUNT rows (found: $ROW_COUNT)" \
  test "$ROW_COUNT" -ge "$PRE_CRASH_ROW_COUNT"

# 5. pg_hba.conf contains repmgr entries on all data nodes
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  HBA_HAS_REPMGR=$(remote_exec "$node_ip" \
    "sudo grep -ci 'repmgr' ${HBA_PATH}" 2>/dev/null | tr -d '[:space:]' || echo "0")
  check "pg_hba.conf on $node_var has repmgr entries (found: $HBA_HAS_REPMGR)" \
    test "$HBA_HAS_REPMGR" -ge 1
done

# 6. pg_hba.conf contains replication entries on all data nodes
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  HBA_HAS_REPL=$(remote_exec "$node_ip" \
    "sudo grep -ci 'replication' ${HBA_PATH}" 2>/dev/null | tr -d '[:space:]' || echo "0")
  check "pg_hba.conf on $node_var has replication entries (found: $HBA_HAS_REPL)" \
    test "$HBA_HAS_REPL" -ge 1
done

# 7. At least 2 standbys streaming from new primary
STREAMING_COUNT=$(pg_exec "$NEW_PRIMARY" \
  "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'" 2>/dev/null || echo "0")
check "At least 2 standbys streaming (found: $STREAMING_COUNT)" \
  test "$STREAMING_COUNT" -ge 2

# 8. Original primary is back as a standby
ORIG_RECOVERY=$(remote_exec "$ORIGINAL_PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null || echo "")
check "Original primary ($ORIGINAL_PRIMARY) rejoined as standby (in_recovery: $ORIG_RECOVERY)" \
  test "$ORIG_RECOVERY" = "t"

# 9. repmgrd running on all nodes
for node_var in NODE1 NODE2 NODE3 NODE4; do
  node_ip="${!node_var}"
  check "repmgrd running on $node_var ($node_ip)" \
    remote_exec "$node_ip" "systemctl is-active ${REPMGRD_SERVICE} 2>/dev/null || systemctl is-active repmgrd"
done

# 10. repmgr cluster show is clean
CLUSTER_NODES=$(repmgr_exec "$NEW_PRIMARY" "cluster show --csv" 2>/dev/null | wc -l | tr -d ' ')
check "repmgr cluster has 4 nodes (found: $CLUSTER_NODES)" \
  test "$CLUSTER_NODES" -ge 4

# 11. Data consistent across nodes
P_COUNT=$(pg_exec "$NEW_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  if [[ "$node_ip" == "$NEW_PRIMARY" ]]; then continue; fi
  S_COUNT=$(pg_exec "$node_ip" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
  check "Data matches on $node_var (primary: $P_COUNT, node: $S_COUNT)" \
    test "$P_COUNT" = "$S_COUNT"
done

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
