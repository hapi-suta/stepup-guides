#!/usr/bin/env bash
# Scenario 03 - Cascading Failure: Primary + one standby crash simultaneously.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-03-state.env"

header "Scenario 03 - Cascading Failure (Primary + Standby Down)"

# ---------- discover current topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
if [[ -z "$PRIMARY" ]]; then
  error "Could not find a running primary. Aborting injection."
  exit 1
fi
info "Current primary: $PRIMARY"

STANDBYS=$(get_standbys)
STANDBY_LIST=($STANDBYS)
if [[ ${#STANDBY_LIST[@]} -lt 2 ]]; then
  error "Need at least 2 standbys. Found: ${#STANDBY_LIST[@]}. Aborting."
  exit 1
fi

VICTIM_STANDBY="${STANDBY_LIST[0]}"
SURVIVING_STANDBY="${STANDBY_LIST[1]}"

info "Victim standby (will crash): $VICTIM_STANDBY"
info "Surviving standby: $SURVIVING_STANDBY"

# ---------- capture pre-crash state ----------
step "Capturing pre-crash state..."
TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees")

cat > "$STATE_FILE" <<EOF
SCENARIO="03-cascading-failure"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
VICTIM_STANDBY="$VICTIM_STANDBY"
SURVIVING_STANDBY="$SURVIVING_STANDBY"
PRE_CRASH_TIMELINE="$TIMELINE"
PRE_CRASH_ROW_COUNT="$ROW_COUNT"
EOF

info "State saved to $STATE_FILE"

# ---------- kill primary and one standby ----------
step "Stopping PostgreSQL on primary ($PRIMARY)..."
remote_exec "$PRIMARY" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"
remote_exec "$PRIMARY" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true

step "Stopping PostgreSQL on standby ($VICTIM_STANDBY)..."
remote_exec "$VICTIM_STANDBY" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"
remote_exec "$VICTIM_STANDBY" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true

success "Both primary ($PRIMARY) and standby ($VICTIM_STANDBY) are DOWN"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: CASCADING FAILURE!"
echo ""
echo "Two nodes are DOWN:"
echo "  - Primary:  $PRIMARY"
echo "  - Standby:  $VICTIM_STANDBY"
echo ""
echo "Only one data node remains: $SURVIVING_STANDBY"
echo "Witness ($NODE4) is still up."
echo ""
echo "repmgrd on the surviving standby may or may not auto-promote"
echo "depending on quorum calculation."
echo ""
echo "Your tasks:"
echo "  1. Check if auto-failover occurred on $SURVIVING_STANDBY"
echo "  2. If not, manually promote the surviving standby"
echo "  3. Verify writes work"
echo "  4. Rejoin BOTH failed nodes as standbys"
echo "  5. Restore full cluster health"
echo "  6. Run validate.sh"
echo "------------------------------------------------------------"
