#!/usr/bin/env bash
# Scenario 01 - Validate: Confirm standby was promoted and writes work.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-01-state.env"

header "Validate - Scenario 01: Primary Crash"

# ---------- load state ----------
if [[ ! -f "$STATE_FILE" ]]; then
  error "State file $STATE_FILE not found. Was inject.sh run?"
  exit 1
fi
source "$STATE_FILE"

# ---------- checks ----------

# 1. State file exists (already confirmed above)
check "State file exists" test -f "$STATE_FILE"

# 2. Original primary is stopped
check "Original primary ($ORIGINAL_PRIMARY) is stopped" \
  bash -c "! ssh $SSH_OPTS ${SSH_USER}@${ORIGINAL_PRIMARY} \
    'sudo -u postgres pg_isready -p ${PG_PORT}' 2>/dev/null"

# 3. One node is now primary (pg_is_in_recovery = f)
NEW_PRIMARY=$(get_primary)
check "A node is running as primary" test -n "$NEW_PRIMARY"

# 4. The promoted node is the former standby
check "Promoted node ($NEW_PRIMARY) is the former standby" \
  test "$NEW_PRIMARY" = "$ORIGINAL_STANDBY"

# 5. Writes succeed on the new primary
WRITE_OK=$(pg_exec "$NEW_PRIMARY" \
  "INSERT INTO employees(name,department) VALUES ('chaos_test','SRE') RETURNING id" 2>/dev/null || echo "")
check "Writes succeed on new primary" test -n "$WRITE_OK"

# 6. Employee data is intact (>= 10000 rows)
ROW_COUNT=$(pg_exec "$NEW_PRIMARY" "SELECT count(*) FROM employees" 2>/dev/null || echo "0")
check "Employee table has >= 10000 rows (found: $ROW_COUNT)" \
  test "$ROW_COUNT" -ge 10000

# 7. Timeline advanced after promotion
NEW_TL=$(pg_exec "$NEW_PRIMARY" \
  "SELECT timeline_id FROM pg_control_checkpoint()" 2>/dev/null || echo "0")
check "Timeline advanced to >= 2 (current: $NEW_TL)" \
  test "$NEW_TL" -ge 2

# ---------- summary ----------
if check_summary; then
  info "Cleaning up state file."
  rm -f "$STATE_FILE"
fi
