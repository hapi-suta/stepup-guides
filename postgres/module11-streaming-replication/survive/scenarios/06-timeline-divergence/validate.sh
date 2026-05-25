#!/usr/bin/env bash
# Scenario 06 - Validate: Confirm one primary, one standby, streaming, data consistent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-06-state.env"

header "Validate - Scenario 06: Timeline Divergence"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists
check "State file exists" test -f "$STATE_FILE"

# 2. At least one node is running as primary
NEW_PRIMARY=$(get_primary)
check "A node is running as primary" test -n "$NEW_PRIMARY"

# 3. At least one node is running as standby
NEW_STANDBY=$(get_standby)
check "A node is running as standby" test -n "$NEW_STANDBY"

# 4. Primary and standby are different nodes
check "Primary ($NEW_PRIMARY) and standby ($NEW_STANDBY) are different nodes" \
  test "$NEW_PRIMARY" != "$NEW_STANDBY"

# 5. Standby is in recovery mode
IN_RECOVERY=$(pg_exec "$NEW_STANDBY" \
  "SELECT pg_is_in_recovery()" 2>/dev/null || echo "")
check "Standby is in recovery mode (got: $IN_RECOVERY)" \
  test "$IN_RECOVERY" = "t"

# 6. Replication is streaming
REPL_STATE=$(pg_exec "$NEW_PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
check "Replication state is 'streaming' (got: $REPL_STATE)" \
  test "$REPL_STATE" = "streaming"

# 7. Both nodes are on the same timeline
TL_PRIMARY=$(pg_exec "$NEW_PRIMARY" \
  "SELECT timeline_id FROM pg_control_checkpoint()" 2>/dev/null || echo "-1")
TL_STANDBY=$(remote_exec "$NEW_STANDBY" \
  "sudo -u postgres /usr/pgsql-16/bin/pg_controldata /var/lib/pgsql/16/data 2>/dev/null \
   | grep 'Latest checkpoint.*TimeLineID' | awk '{print \$NF}'" | tr -d '[:space:]')
check "Both nodes on same timeline (primary: $TL_PRIMARY, standby: $TL_STANDBY)" \
  test "$TL_PRIMARY" = "$TL_STANDBY"

# 8. Data is consistent between primary and standby
P_COUNT=$(pg_exec "$NEW_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-1")
S_COUNT=$(pg_exec "$NEW_STANDBY" "SELECT count(*) FROM employees" 2>/dev/null || echo "-2")
check "Employee counts match (primary: $P_COUNT, standby: $S_COUNT)" \
  test "$P_COUNT" = "$S_COUNT"

# 9. Writes succeed on the primary
WRITE_OK=$(pg_exec "$NEW_PRIMARY" \
  "INSERT INTO employees(name,department) VALUES ('timeline_test','SRE') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on primary" test -n "$WRITE_OK"

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
