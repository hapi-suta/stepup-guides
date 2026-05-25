#!/usr/bin/env bash
# Scenario 02 - Validate: Confirm replication caught up and is healthy.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-02-state.env"
LAG_THRESHOLD=1048576  # 1 MB in bytes

header "Validate - Scenario 02: Replication Lag"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. Replication is streaming
REPL_STATE=$(pg_exec "$PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
check "Replication state is 'streaming' (got: $REPL_STATE)" \
  test "$REPL_STATE" = "streaming"

# 3. Replication lag is under threshold
CURRENT_LAG=$(pg_exec "$PRIMARY" \
  "SELECT coalesce(pg_wal_lsn_diff(sent_lsn, replay_lsn)::bigint, 0) FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "999999999")
check "Replication lag under 1 MB (current: $CURRENT_LAG bytes)" \
  test "$CURRENT_LAG" -lt "$LAG_THRESHOLD"

# 4. Replication slot is active
SLOT_ACTIVE=$(pg_exec "$PRIMARY" \
  "SELECT active FROM pg_replication_slots WHERE slot_name='standby_slot'" 2>/dev/null || echo "")
check "Replication slot 'standby_slot' is active (got: $SLOT_ACTIVE)" \
  test "$SLOT_ACTIVE" = "t"

# 5. pgbench load is no longer running
PGBENCH_RUNNING=$(remote_exec "$PRIMARY" "pgrep -c pgbench 2>/dev/null || echo 0" | tr -d '[:space:]')
check "pgbench load process is stopped (running: $PGBENCH_RUNNING)" \
  test "$PGBENCH_RUNNING" -eq 0

# 6. Data is consistent between primary and standby
P_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
S_COUNT=$(pg_exec "$STANDBY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
check "Employee counts match (primary: $P_COUNT, standby: $S_COUNT)" \
  test "$P_COUNT" = "$S_COUNT"

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
