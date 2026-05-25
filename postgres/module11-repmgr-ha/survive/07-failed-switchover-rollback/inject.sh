#!/usr/bin/env bash
# Scenario 07 - Failed Switchover Rollback: Start a switchover then kill
# repmgrd mid-way, leaving the cluster in a mixed state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-07-state.env"

header "Scenario 07 - Failed Switchover Rollback"

# ---------- discover current topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
if [[ -z "$PRIMARY" ]]; then
  error "Could not find a running primary. Aborting injection."
  exit 1
fi
info "Current primary: $PRIMARY"

STANDBYS=$(get_standbys)
TARGET_STANDBY=$(echo "$STANDBYS" | head -1)
info "Current standbys: $(echo "$STANDBYS" | tr '\n' ' ')"
info "Switchover target: $TARGET_STANDBY"

if [[ -z "$TARGET_STANDBY" ]]; then
  error "Could not find a standby for switchover. Aborting injection."
  exit 1
fi

# ---------- capture pre-switchover state ----------
step "Capturing pre-switchover state..."
TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees")

# Get the target standby's node ID for the switchover command
TARGET_HOSTNAME=$(remote_exec "$TARGET_STANDBY" "hostname")
TARGET_NODE_ID=$(pg_exec "$PRIMARY" \
  "SELECT node_id FROM repmgr.nodes WHERE node_name='${TARGET_HOSTNAME}'" 2>/dev/null || echo "")

cat > "$STATE_FILE" <<EOF
SCENARIO="07-failed-switchover-rollback"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBYS="$(echo "$STANDBYS" | tr '\n' ',')"
TARGET_STANDBY="$TARGET_STANDBY"
TARGET_HOSTNAME="$TARGET_HOSTNAME"
TARGET_NODE_ID="$TARGET_NODE_ID"
PRE_SWITCHOVER_TIMELINE="$TIMELINE"
PRE_SWITCHOVER_ROW_COUNT="$ROW_COUNT"
EOF

info "State saved to $STATE_FILE"

# ---------- simulate a failed switchover ----------
# Step 1: Demote the primary by stopping PostgreSQL on it
step "Demoting original primary ($PRIMARY) - stopping PostgreSQL..."
remote_exec "$PRIMARY" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"
remote_exec "$PRIMARY" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true

success "Primary ($PRIMARY) is stopped (demoted)"

# Step 2: Do NOT promote the target - leave the cluster with no primary
# Stop repmgrd on all nodes so nothing auto-heals
step "Stopping repmgrd on all remaining nodes..."
for node in "$NODE1" "$NODE2" "$NODE3" "$NODE4"; do
  remote_exec "$node" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true
done

success "repmgrd stopped on all nodes"

# Step 3: Corrupt repmgr metadata to show switchover was "in progress"
# Mark the old primary as failed and the target as primary in metadata only
step "Corrupting metadata to simulate mid-switchover state..."
pg_exec "$TARGET_STANDBY" \
  "UPDATE repmgr.nodes SET active=false WHERE node_name IN (
     SELECT node_name FROM repmgr.nodes WHERE type='primary'
   )" 2>/dev/null || true

success "Metadata shows old primary as inactive"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: SWITCHOVER FAILED MID-WAY!"
echo ""
echo "A switchover from $PRIMARY to $TARGET_STANDBY was interrupted."
echo ""
echo "Current state:"
echo "  - Old primary ($PRIMARY): PostgreSQL STOPPED, repmgrd STOPPED"
echo "  - Target standby ($TARGET_STANDBY): Still in recovery (NOT promoted)"
echo "  - Other standbys: Still following old primary (which is down)"
echo "  - repmgrd: STOPPED on all nodes"
echo "  - Metadata: Partially updated (old primary marked inactive)"
echo ""
echo "The cluster has NO functioning primary. All writes are blocked."
echo ""
echo "Your tasks:"
echo "  1. Assess actual state with pg_is_in_recovery() on each node"
echo "  2. Promote the intended target standby"
echo "  3. Redirect other standbys to follow the new primary"
echo "  4. Rejoin the old primary as a standby"
echo "  5. Fix metadata and restart repmgrd"
echo "  6. Run validate.sh"
echo "------------------------------------------------------------"
