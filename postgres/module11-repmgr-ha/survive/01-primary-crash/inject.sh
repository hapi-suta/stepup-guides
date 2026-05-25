#!/usr/bin/env bash
# Scenario 01 - Primary Crash: Kill PostgreSQL on the primary node.
# repmgrd should auto-promote a standby.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-01-state.env"

header "Scenario 01 - Primary Crash (repmgr auto-failover)"

# ---------- discover current primary ----------
step "Discovering current primary..."
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
LSN=$(pg_exec "$PRIMARY" "SELECT pg_current_wal_lsn()")
NODE_COUNT=$(repmgr_exec "$PRIMARY" "cluster show --csv" 2>/dev/null | wc -l | tr -d ' ')

cat > "$STATE_FILE" <<EOF
SCENARIO="01-primary-crash"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBYS="$(echo "$STANDBYS" | tr '\n' ',')"
PRE_CRASH_TIMELINE="$TIMELINE"
PRE_CRASH_LSN="$LSN"
PRE_CRASH_NODE_COUNT="$NODE_COUNT"
EOF

info "State saved to $STATE_FILE"

# ---------- kill the primary ----------
step "Stopping PostgreSQL on primary ($PRIMARY)..."
remote_exec "$PRIMARY" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"

# Also stop repmgrd on the primary to prevent it from auto-restarting PG
remote_exec "$PRIMARY" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true

success "PostgreSQL and repmgrd stopped on $PRIMARY"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: PostgreSQL primary ($PRIMARY) is DOWN."
echo ""
echo "repmgrd on the standbys should detect the failure and"
echo "auto-promote one of them within ~60 seconds."
echo ""
echo "Monitor the repmgr log on the standbys:"
echo "  tail -f /var/lib/pgsql/16/data/log/repmgrd.log"
echo ""
echo "After auto-failover completes:"
echo "  1. Verify the new topology with repmgr cluster show"
echo "  2. Rejoin the old primary as a standby"
echo "  3. Verify data integrity"
echo "  4. Run validate.sh"
echo "------------------------------------------------------------"
