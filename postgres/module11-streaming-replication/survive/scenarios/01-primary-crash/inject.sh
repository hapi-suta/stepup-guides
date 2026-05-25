#!/usr/bin/env bash
# Scenario 01 - Primary Crash: Kill PostgreSQL on the primary node.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-01-state.env"

header "Scenario 01 - Primary Crash"

# ---------- discover current primary ----------
step "Discovering current primary..."
PRIMARY=$(get_primary)
if [[ -z "$PRIMARY" ]]; then
  error "Could not find a running primary. Aborting injection."
  exit 1
fi
info "Current primary: $PRIMARY"

STANDBY=$(get_standby)
info "Current standby: $STANDBY"

# ---------- capture pre-crash state ----------
step "Capturing pre-crash state..."
TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
LSN=$(pg_exec "$PRIMARY" "SELECT pg_current_wal_lsn()")

cat > "$STATE_FILE" <<EOF
SCENARIO="01-primary-crash"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBY="$STANDBY"
PRE_CRASH_TIMELINE="$TIMELINE"
PRE_CRASH_LSN="$LSN"
EOF

info "State saved to $STATE_FILE"

# ---------- kill the primary ----------
step "Stopping PostgreSQL on primary ($PRIMARY)..."
remote_exec "$PRIMARY" "sudo systemctl stop postgresql-16"

success "PostgreSQL stopped on $PRIMARY"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: PostgreSQL primary ($PRIMARY) is DOWN."
echo "Streaming replication has stopped. Standby ($STANDBY) is"
echo "still in recovery mode - no writes are being accepted."
echo "Follow the runbook to promote the standby and restore service."
echo "------------------------------------------------------------"
