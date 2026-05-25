#!/usr/bin/env bash
# Scenario 08 - Validate: Confirm replication restored, standby in recovery, data consistent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-08-state.env"

header "Validate - Scenario 08: pg_hba Lockout"

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
check "Primary ($PRIMARY) PostgreSQL is running" \
  remote_exec "$PRIMARY" "sudo -u postgres pg_isready -p ${PG_PORT}"

# 3. Standby is running
check "Standby ($STANDBY) PostgreSQL is running" \
  remote_exec "$STANDBY" "sudo -u postgres pg_isready -p ${PG_PORT}"

# 4. Standby is in recovery mode
IN_RECOVERY=$(pg_exec "$STANDBY" \
  "SELECT pg_is_in_recovery()" 2>/dev/null || echo "")
check "Standby is in recovery mode (got: $IN_RECOVERY)" \
  test "$IN_RECOVERY" = "t"

# 5. pg_hba.conf has a replication entry
HBA_REPL=$(remote_exec "$PRIMARY" \
  "sudo grep -c 'replication' '${HBA_FILE}'" 2>/dev/null | tr -d '[:space:]')
check "pg_hba.conf has replication entry (count: $HBA_REPL)" \
  test "$HBA_REPL" -gt 0

# 6. Replication is streaming
REPL_STATE=$(pg_exec "$PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
check "Replication state is 'streaming' (got: $REPL_STATE)" \
  test "$REPL_STATE" = "streaming"

# 7. Data is consistent between primary and standby
P_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
S_COUNT=$(pg_exec "$STANDBY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
check "Employee counts match (primary: $P_COUNT, standby: $S_COUNT)" \
  test "$P_COUNT" = "$S_COUNT"

# 8. Backup pg_hba.conf cleaned up
BAK_EXISTS=$(remote_exec "$PRIMARY" \
  "test -f '${HBA_FILE}.bak' && echo yes || echo no" 2>/dev/null)
check "Backup pg_hba.conf cleaned up (bak exists: $BAK_EXISTS)" \
  test "$BAK_EXISTS" = "no"

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
