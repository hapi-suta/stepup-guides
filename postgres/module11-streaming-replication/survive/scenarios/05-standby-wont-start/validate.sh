#!/usr/bin/env bash
# Scenario 05 - Validate: Confirm standby is running, in recovery, and streaming.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-05-state.env"

header "Validate - Scenario 05: Standby Won't Start"

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

# 4. standby.signal exists
SIGNAL_EXISTS=$(remote_exec "$STANDBY" \
  "test -f '${DATA_DIR}/standby.signal' && echo yes || echo no" 2>/dev/null)
check "standby.signal exists (got: $SIGNAL_EXISTS)" \
  test "$SIGNAL_EXISTS" = "yes"

# 5. primary_conninfo is valid (not pointing to 999.999.999.999)
CONNINFO=$(remote_exec "$STANDBY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SHOW primary_conninfo\"" 2>/dev/null || echo "")
BAD_HOST=$(echo "$CONNINFO" | grep -c "999.999.999.999" || true)
check "primary_conninfo does not contain bogus host (bad matches: $BAD_HOST)" \
  test "$BAD_HOST" -eq 0

# 6. Replication is streaming
REPL_STATE=$(pg_exec "$PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
check "Replication state is 'streaming' (got: $REPL_STATE)" \
  test "$REPL_STATE" = "streaming"

# 7. Data matches between primary and standby
P_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
S_COUNT=$(pg_exec "$STANDBY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
check "Employee counts match (primary: $P_COUNT, standby: $S_COUNT)" \
  test "$P_COUNT" = "$S_COUNT"

# 8. Backup files cleaned up
BAK_SIGNAL=$(remote_exec "$STANDBY" \
  "test -f '${DATA_DIR}/standby.signal.bak' && echo yes || echo no" 2>/dev/null)
BAK_CONF=$(remote_exec "$STANDBY" \
  "test -f '${DATA_DIR}/postgresql.auto.conf.bak' && echo yes || echo no" 2>/dev/null)
check "Backup files cleaned up (signal.bak: $BAK_SIGNAL, conf.bak: $BAK_CONF)" \
  test "$BAK_SIGNAL" = "no" -a "$BAK_CONF" = "no"

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
