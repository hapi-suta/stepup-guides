#!/usr/bin/env bash
# Scenario 04 - Witness Failure: Kill the witness, then kill the primary.
# Tests failover behavior without the quorum voter.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/stepup-repmgr-04-state.env"

header "Scenario 04 - Witness Failure During Primary Crash"

# ---------- discover current topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
if [[ -z "$PRIMARY" ]]; then
  error "Could not find a running primary. Aborting injection."
  exit 1
fi
info "Current primary: $PRIMARY"

STANDBYS=$(get_standbys)
info "Current standbys: $(echo "$STANDBYS" | tr '\n' ' ')"

# ---------- capture pre-crash state ----------
step "Capturing pre-crash state..."
TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees")

cat > "$STATE_FILE" <<EOF
SCENARIO="04-witness-failure"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBYS="$(echo "$STANDBYS" | tr '\n' ',')"
WITNESS_NODE="$NODE4"
PRE_CRASH_TIMELINE="$TIMELINE"
PRE_CRASH_ROW_COUNT="$ROW_COUNT"
EOF

info "State saved to $STATE_FILE"

# ---------- kill the witness first ----------
step "Stopping PostgreSQL on witness ($NODE4)..."
remote_exec "$NODE4" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"
remote_exec "$NODE4" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true

success "Witness ($NODE4) is DOWN"

# Wait a moment for the cluster to notice
sleep 5

# ---------- then kill the primary ----------
step "Stopping PostgreSQL on primary ($PRIMARY)..."
remote_exec "$PRIMARY" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"
remote_exec "$PRIMARY" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true

success "Primary ($PRIMARY) is DOWN"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: DOUBLE FAILURE - Witness AND Primary are DOWN!"
echo ""
echo "Witness ($NODE4) went down first, then primary ($PRIMARY)."
echo ""
echo "Standbys need the witness for quorum during failover."
echo "Without the witness, repmgrd may NOT auto-promote."
echo ""
echo "Your tasks:"
echo "  1. Check repmgr logs on standbys for failover attempts"
echo "  2. If auto-failover did not occur, promote manually"
echo "  3. Verify writes on the new primary"
echo "  4. Bring the witness back online"
echo "  5. Rejoin the old primary as a standby"
echo "  6. Restore full cluster health"
echo "  7. Run validate.sh"
echo "------------------------------------------------------------"
