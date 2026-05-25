#!/usr/bin/env bash
# Scenario 05 - repmgrd Stuck: Stop repmgrd on all standbys, then crash primary.
# Without repmgrd, there is no automatic failover - manual intervention needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-05-state.env"

header "Scenario 05 - repmgrd Stuck (No Auto-Failover)"

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
SCENARIO="05-repmgrd-stuck"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBYS="$(echo "$STANDBYS" | tr '\n' ',')"
PRE_CRASH_TIMELINE="$TIMELINE"
PRE_CRASH_ROW_COUNT="$ROW_COUNT"
EOF

info "State saved to $STATE_FILE"

# ---------- kill repmgrd on ALL nodes ----------
step "Stopping repmgrd on ALL nodes..."
for node in "$NODE1" "$NODE2" "$NODE3" "$NODE4"; do
  remote_exec "$node" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true
done

success "repmgrd stopped on all 4 nodes"

# ---------- corrupt repmgrd config on standbys ----------
# Rename the config file to simulate a stuck/broken repmgrd
step "Renaming repmgr.conf on standbys to simulate stuck daemon..."
for standby in $STANDBYS; do
  remote_exec "$standby" \
    "sudo cp ${REPMGR_CONF} ${REPMGR_CONF}.backup" 2>/dev/null || true
  remote_exec "$standby" \
    "echo '# CORRUPTED - repmgrd will not start' | sudo tee ${REPMGR_CONF} >/dev/null" 2>/dev/null || true
done

success "repmgr.conf corrupted on standbys"

# ---------- crash the primary ----------
step "Stopping PostgreSQL on primary ($PRIMARY)..."
remote_exec "$PRIMARY" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"

success "Primary ($PRIMARY) is DOWN"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: PRIMARY DOWN - NO AUTOMATIC FAILOVER!"
echo ""
echo "PostgreSQL primary ($PRIMARY) has crashed."
echo "repmgrd is NOT running on any node."
echo "repmgr.conf on standbys has been corrupted."
echo ""
echo "There will be NO auto-promotion. You must:"
echo "  1. Fix repmgr.conf on the standbys (backup at ${REPMGR_CONF}.backup)"
echo "  2. Manually promote a standby"
echo "  3. Redirect other standbys to the new primary"
echo "  4. Rejoin the old primary"
echo "  5. Restart repmgrd on all nodes"
echo "  6. Run validate.sh"
echo ""
echo "This scenario tests whether you can recover WITHOUT"
echo "the safety net of automatic failover."
echo "------------------------------------------------------------"
