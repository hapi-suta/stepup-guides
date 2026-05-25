#!/usr/bin/env bash
# Scenario 09 - pg_hba Blocks repmgr: Remove repmgr user's HBA entries on
# primary, reload, then crash the primary. New primary inherits broken HBA.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/stepup-repmgr-09-state.env"

header "Scenario 09 - pg_hba Blocks repmgr"

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

# ---------- capture pre-corruption state ----------
step "Capturing pre-corruption state..."
TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees")

# On CentOS, pg_hba.conf is in the data directory
HBA_PATH="${PG_DATA}/pg_hba.conf"

cat > "$STATE_FILE" <<EOF
SCENARIO="09-pg-hba-blocks-repmgr"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBYS="$(echo "$STANDBYS" | tr '\n' ',')"
PRE_CRASH_TIMELINE="$TIMELINE"
PRE_CRASH_ROW_COUNT="$ROW_COUNT"
HBA_PATH="$HBA_PATH"
EOF

info "State saved to $STATE_FILE"

# ---------- corrupt pg_hba.conf on ALL data nodes ----------
# Remove repmgr and replication entries from pg_hba.conf on all nodes.
# This way, whichever standby gets promoted will inherit the broken config.
step "Backing up and corrupting pg_hba.conf on all data nodes..."

for node in "$NODE1" "$NODE2" "$NODE3"; do
  # Backup original
  remote_exec "$node" \
    "sudo cp ${HBA_PATH} ${HBA_PATH}.backup" 2>/dev/null || true

  # Remove lines containing 'repmgr' or 'replication' (case-insensitive)
  remote_exec "$node" \
    "sudo grep -iv 'repmgr\|replication' ${HBA_PATH} | sudo tee ${HBA_PATH}.tmp >/dev/null && \
     sudo mv ${HBA_PATH}.tmp ${HBA_PATH} && \
     sudo chown postgres:postgres ${HBA_PATH}" 2>/dev/null || true

  # Reload to apply
  remote_exec "$node" \
    "sudo -u postgres psql -p ${PG_PORT} -c 'SELECT pg_reload_conf()'" 2>/dev/null || true
done

success "pg_hba.conf corrupted on all data nodes (repmgr/replication entries removed)"

# ---------- crash the primary ----------
step "Stopping PostgreSQL on primary ($PRIMARY)..."
remote_exec "$PRIMARY" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"
remote_exec "$PRIMARY" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true

success "Primary ($PRIMARY) is DOWN"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: PRIMARY DOWN - REPLICATION WILL FAIL ON NEW PRIMARY!"
echo ""
echo "PostgreSQL primary ($PRIMARY) has crashed."
echo ""
echo "repmgrd should auto-promote a standby, but the new primary"
echo "has a BROKEN pg_hba.conf - repmgr and replication entries"
echo "have been removed from ALL data nodes."
echo ""
echo "After failover, standbys will NOT be able to connect to the"
echo "new primary for replication."
echo ""
echo "Your tasks:"
echo "  1. Wait for auto-promotion (or promote manually)"
echo "  2. Diagnose why standbys cannot replicate from new primary"
echo "  3. Fix pg_hba.conf on the new primary (backup at ${HBA_PATH}.backup)"
echo "  4. Fix pg_hba.conf on ALL nodes"
echo "  5. Reload PostgreSQL config"
echo "  6. Verify standbys reconnect and start streaming"
echo "  7. Rejoin the old primary"
echo "  8. Run validate.sh"
echo "------------------------------------------------------------"
