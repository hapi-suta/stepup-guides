#!/usr/bin/env bash
# Scenario 10 - Validate: Confirm replication recovered and no dangling iptables rules.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-10-state.env"
LAG_THRESHOLD=1048576  # 1 MB in bytes

header "Validate - Scenario 10: Network Flap"

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

# 5. Replication lag under threshold
CURRENT_LAG=$(pg_exec "$PRIMARY" \
  "SELECT coalesce(pg_wal_lsn_diff(sent_lsn, replay_lsn)::bigint, 0) FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "999999999")
check "Replication lag under 1 MB (current: $CURRENT_LAG bytes)" \
  test "$CURRENT_LAG" -lt "$LAG_THRESHOLD"

# 6. No iptables rules blocking port 5432 on standby
IPTABLES_STANDBY=$(remote_exec "$STANDBY" \
  "sudo iptables -L -n 2>/dev/null | grep -c '${PG_PORT}' || echo 0" | tr -d '[:space:]')
check "No iptables rules blocking port ${PG_PORT} on standby (found: $IPTABLES_STANDBY)" \
  test "$IPTABLES_STANDBY" -eq 0

# 7. No iptables rules blocking port 5432 on primary
IPTABLES_PRIMARY=$(remote_exec "$PRIMARY" \
  "sudo iptables -L -n 2>/dev/null | grep -c '${PG_PORT}' || echo 0" | tr -d '[:space:]')
check "No iptables rules blocking port ${PG_PORT} on primary (found: $IPTABLES_PRIMARY)" \
  test "$IPTABLES_PRIMARY" -eq 0

# 8. Data matches between primary and standby
P_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
S_COUNT=$(pg_exec "$STANDBY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
check "Employee counts match (primary: $P_COUNT, standby: $S_COUNT)" \
  test "$P_COUNT" = "$S_COUNT"

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
