#!/usr/bin/env bash
# Scenario 10 - Validate: Confirm disk freed, PG running, replication streaming.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/stepup-repmgr-10-state.env"

header "Validate - Scenario 10: Disk Full on Primary"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. Primary is running
PRIMARY=$(get_primary)
check "A primary is running" test -n "$PRIMARY"

# 3. No fill files remain in pg_wal
FILL_FILES=$(remote_exec "$PRIMARY" \
  "find ${PG_DATA}/pg_wal -name 'FILL_DISK*' -o -name '*CHAOS*' 2>/dev/null | wc -l" 2>/dev/null | tr -d '[:space:]' || echo "0")
check "No fill files remain in pg_wal (found: $FILL_FILES)" \
  test "$FILL_FILES" -eq 0

# 4. Disk usage under 90%
DISK_PCT=$(remote_exec "$PRIMARY" \
  "df ${PG_DATA}/pg_wal | tail -1 | awk '{print \$5}' | tr -d '%'" 2>/dev/null | tr -d '[:space:]' || echo "100")
check "Disk usage under 90% (current: ${DISK_PCT}%)" \
  test "$DISK_PCT" -lt 90

# 5. PostgreSQL is accepting connections
check "PostgreSQL accepting connections on primary ($PRIMARY)" \
  remote_exec "$PRIMARY" "sudo -u postgres ${PG_BIN}/pg_isready -p ${PG_PORT}"

# 6. Writes succeed
WRITE_OK=$(pg_exec "$PRIMARY" \
  "INSERT INTO employees(name, department) VALUES ('diskfull_validate','SRE') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on primary ($PRIMARY)" test -n "$WRITE_OK"

# 7. Data integrity
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "0")
check "Employee table has >= $PRE_FILL_ROW_COUNT rows (found: $ROW_COUNT)" \
  test "$ROW_COUNT" -ge "$PRE_FILL_ROW_COUNT"

# 8. WAL position is advancing (two reads 1 second apart)
LSN1=$(pg_exec "$PRIMARY" "SELECT pg_current_wal_lsn()" 2>/dev/null || echo "0/0")
pg_exec "$PRIMARY" \
  "INSERT INTO employees(name, department) VALUES ('wal_advance_test','SRE')" 2>/dev/null || true
LSN2=$(pg_exec "$PRIMARY" "SELECT pg_current_wal_lsn()" 2>/dev/null || echo "0/0")
check "WAL position advancing (was: $LSN1, now: $LSN2)" \
  test "$LSN1" != "$LSN2"

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

# 11. Data consistent across nodes
P_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
for node_var in NODE1 NODE2 NODE3; do
  node_ip="${!node_var}"
  if [[ "$node_ip" == "$PRIMARY" ]]; then continue; fi
  S_COUNT=$(pg_exec "$node_ip" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
  check "Data matches on $node_var (primary: $P_COUNT, node: $S_COUNT)" \
    test "$P_COUNT" = "$S_COUNT"
done

# 12. repmgr cluster show is clean
CLUSTER_NODES=$(repmgr_exec "$PRIMARY" "cluster show --csv" 2>/dev/null | wc -l | tr -d ' ')
check "repmgr cluster has 4 nodes (found: $CLUSTER_NODES)" \
  test "$CLUSTER_NODES" -ge 4

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
