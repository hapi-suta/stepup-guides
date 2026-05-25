#!/usr/bin/env bash
# Scenario 07 - Validate: Confirm archive_command working, failures stopped, WAL archived.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-07-state.env"

header "Validate - Scenario 07: Archive Command Failure"

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

# 3. Archive directory is accessible
ARCHIVE_PERMS=$(remote_exec "$PRIMARY" \
  "sudo stat -c '%a' '${ARCHIVE_DIR}'" 2>/dev/null | tr -d '[:space:]')
check "Archive directory has proper permissions (got: $ARCHIVE_PERMS)" \
  test "$ARCHIVE_PERMS" -ge 700

# 4. Archive_command is succeeding - trigger a WAL switch and check
remote_exec "$PRIMARY" "sudo -u postgres psql -p ${PG_PORT} -c 'SELECT pg_switch_wal()'" >/dev/null 2>&1
sleep 3

LAST_ARCHIVED_TIME=$(remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \
    \"SELECT extract(epoch FROM (now() - last_archived_time))::int FROM pg_stat_archiver\"" 2>/dev/null | tr -d '[:space:]')
check "Last successful archive was recent - within 60s (got: ${LAST_ARCHIVED_TIME}s ago)" \
  test "$LAST_ARCHIVED_TIME" -lt 60

# 5. Failed count is not increasing - snapshot twice with a gap
FAIL_1=$(remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SELECT failed_count FROM pg_stat_archiver\"" 2>/dev/null | tr -d '[:space:]')
sleep 5
FAIL_2=$(remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SELECT failed_count FROM pg_stat_archiver\"" 2>/dev/null | tr -d '[:space:]')
check "Archive failed_count not increasing (before: $FAIL_1, after: $FAIL_2)" \
  test "$FAIL_1" = "$FAIL_2"

# 6. Archive directory contains WAL files
WAL_COUNT=$(remote_exec "$PRIMARY" \
  "sudo -iu postgres bash -c 'ls ${ARCHIVE_DIR}/ 2>/dev/null | wc -l'" | tr -d '[:space:]')
check "Archive directory contains WAL files (count: $WAL_COUNT)" \
  test "$WAL_COUNT" -gt 0

# 7. Replication is streaming
REPL_STATE=$(pg_exec "$PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
check "Replication state is 'streaming' (got: $REPL_STATE)" \
  test "$REPL_STATE" = "streaming"

# 8. Data is consistent between primary and standby
P_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
S_COUNT=$(pg_exec "$STANDBY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
check "Employee counts match (primary: $P_COUNT, standby: $S_COUNT)" \
  test "$P_COUNT" = "$S_COUNT"

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
