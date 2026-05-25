#!/usr/bin/env bash
# Scenario 03 - Validate: Confirm standby recovered and is streaming.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-03-state.env"

header "Validate - Scenario 03: WAL Corruption"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. Standby is running
check "Standby ($STANDBY) PostgreSQL is running" \
  remote_exec "$STANDBY" "sudo -u postgres pg_isready -p ${PG_PORT}"

# 3. Standby is in recovery mode
IN_RECOVERY=$(pg_exec "$STANDBY" \
  "SELECT pg_is_in_recovery()" 2>/dev/null || echo "")
check "Standby is in recovery mode (got: $IN_RECOVERY)" \
  test "$IN_RECOVERY" = "t"

# 4. Replication is streaming from primary
REPL_STATE=$(pg_exec "$PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
check "Replication state is 'streaming' (got: $REPL_STATE)" \
  test "$REPL_STATE" = "streaming"

# 5. No unexpected FATAL/PANIC in recent log
# Exclude benign "terminating walreceiver" messages that occur during normal restarts
ERRORS=$(remote_exec "$STANDBY" \
  "sudo tail -50 /var/lib/pgsql/16/data/log/postgresql-*.log 2>/dev/null \
   | grep -E 'FATAL|PANIC' | grep -cv 'terminating walreceiver'" 2>/dev/null | tr -d '[:space:]')
ERRORS=${ERRORS:-0}
check "No unexpected FATAL/PANIC in standby log (found: $ERRORS)" \
  test "$ERRORS" -eq 0

# 6. Data matches between primary and standby
P_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
S_COUNT=$(pg_exec "$STANDBY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
check "Employee counts match (primary: $P_COUNT, standby: $S_COUNT)" \
  test "$P_COUNT" = "$S_COUNT"

# 7. Corrupt file cleaned up
CORRUPT_EXISTS=$(remote_exec "$STANDBY" \
  "test -f '${WAL_DIR}/${CORRUPT_FILE}' && echo yes || echo no" 2>/dev/null)
check "Corrupt WAL file cleaned up (exists: $CORRUPT_EXISTS)" \
  test "$CORRUPT_EXISTS" = "no"

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
