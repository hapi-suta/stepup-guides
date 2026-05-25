#!/usr/bin/env bash
# Scenario 09 - Validate: Confirm standby recovered from OOM kill and is streaming.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-09-state.env"

header "Validate - Scenario 09: OOM Kill on Standby"

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

# 4. Replication is streaming
REPL_STATE=$(pg_exec "$PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
check "Replication state is 'streaming' (got: $REPL_STATE)" \
  test "$REPL_STATE" = "streaming"

# 5. No stale PID file issues (process matches PID file)
PID_FILE_PID=$(remote_exec "$STANDBY" \
  "sudo -u postgres head -1 /var/lib/pgsql/16/data/postmaster.pid 2>/dev/null" | tr -d '[:space:]')
PID_ALIVE=$(remote_exec "$STANDBY" \
  "sudo kill -0 ${PID_FILE_PID} 2>/dev/null && echo yes || echo no" | tr -d '[:space:]')
check "Postmaster PID ($PID_FILE_PID) is alive (got: $PID_ALIVE)" \
  test "$PID_ALIVE" = "yes"

# 6. Data matches between primary and standby
P_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
S_COUNT=$(pg_exec "$STANDBY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
check "Employee counts match (primary: $P_COUNT, standby: $S_COUNT)" \
  test "$P_COUNT" = "$S_COUNT"

# 7. Replication lag is reasonable (under 1 MB)
LAG_THRESHOLD=1048576
CURRENT_LAG=$(pg_exec "$PRIMARY" \
  "SELECT coalesce(pg_wal_lsn_diff(sent_lsn, replay_lsn)::bigint, 0) FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "999999999")
check "Replication lag under 1 MB (current: $CURRENT_LAG bytes)" \
  test "$CURRENT_LAG" -lt "$LAG_THRESHOLD"

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
