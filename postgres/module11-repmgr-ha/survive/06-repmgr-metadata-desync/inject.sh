#!/usr/bin/env bash
# Scenario 06 - repmgr Metadata Desync: Corrupt repmgr.nodes so metadata
# disagrees with actual PostgreSQL roles.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-repmgr-06-state.env"

header "Scenario 06 - repmgr Metadata Desync"

# ---------- discover current topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
if [[ -z "$PRIMARY" ]]; then
  error "Could not find a running primary. Aborting injection."
  exit 1
fi
info "Current primary: $PRIMARY"

STANDBYS=$(get_standbys)
FIRST_STANDBY=$(echo "$STANDBYS" | head -1)
info "Current standbys: $(echo "$STANDBYS" | tr '\n' ' ')"

if [[ -z "$FIRST_STANDBY" ]]; then
  error "Could not find a running standby. Aborting injection."
  exit 1
fi

# ---------- capture pre-corruption state ----------
step "Capturing pre-corruption state..."
# Query repmgr database for metadata
repmgr_db_exec() {
  local host="$1" sql="$2"
  remote_exec "$host" \
    "sudo -u postgres psql -p ${PG_PORT} -d repmgr -t -A -c \"${sql}\""
}

PRIMARY_NODE_ID=$(repmgr_db_exec "$PRIMARY" \
  "SELECT node_id FROM repmgr.nodes WHERE type='primary' LIMIT 1")
STANDBY_NODE_ID=$(repmgr_db_exec "$FIRST_STANDBY" \
  "SELECT node_id FROM repmgr.nodes WHERE conninfo LIKE '%$(remote_exec "$FIRST_STANDBY" "hostname")%' LIMIT 1" 2>/dev/null || echo "")

# If we could not resolve by hostname, grab the first standby node_id
if [[ -z "$STANDBY_NODE_ID" ]]; then
  STANDBY_NODE_ID=$(repmgr_db_exec "$PRIMARY" \
    "SELECT node_id FROM repmgr.nodes WHERE type='standby' LIMIT 1")
fi

TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees")

cat > "$STATE_FILE" <<EOF
SCENARIO="06-repmgr-metadata-desync"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBYS="$(echo "$STANDBYS" | tr '\n' ',')"
FIRST_STANDBY="$FIRST_STANDBY"
PRIMARY_NODE_ID="$PRIMARY_NODE_ID"
STANDBY_NODE_ID="$STANDBY_NODE_ID"
PRE_CORRUPT_TIMELINE="$TIMELINE"
PRE_CORRUPT_ROW_COUNT="$ROW_COUNT"
EOF

info "State saved to $STATE_FILE"

# ---------- corrupt repmgr metadata ----------
# Swap the type values: mark the actual primary as standby and the actual
# standby as primary in repmgr.nodes. This makes repmgr cluster show
# display completely wrong roles.
step "Corrupting repmgr.nodes metadata on primary..."
repmgr_db_exec "$PRIMARY" \
  "UPDATE repmgr.nodes SET type='standby', active=true WHERE node_id=${PRIMARY_NODE_ID}"
repmgr_db_exec "$PRIMARY" \
  "UPDATE repmgr.nodes SET type='primary', active=true WHERE node_id=${STANDBY_NODE_ID}"

success "Metadata corrupted: node $PRIMARY_NODE_ID marked as standby, node $STANDBY_NODE_ID marked as primary"

# ---------- stop repmgrd so it does not self-heal ----------
step "Stopping repmgrd on all nodes to prevent auto-correction..."
for node in "$NODE1" "$NODE2" "$NODE3" "$NODE4"; do
  remote_exec "$node" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true
done

success "repmgrd stopped on all nodes"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: repmgr metadata is DESYNCHRONIZED!"
echo ""
echo "repmgr.nodes table has been corrupted:"
echo "  - Node $PRIMARY_NODE_ID (actual primary) is marked as 'standby'"
echo "  - Node $STANDBY_NODE_ID (actual standby) is marked as 'primary'"
echo ""
echo "repmgr cluster show will display WRONG roles."
echo "PostgreSQL itself is fine - replication is still streaming."
echo ""
echo "Your tasks:"
echo "  1. Run repmgr cluster show and compare with pg_is_in_recovery()"
echo "  2. Identify the actual primary and standbys"
echo "  3. Fix the metadata (re-register nodes or manual UPDATE)"
echo "  4. Restart repmgrd on all nodes"
echo "  5. Run validate.sh"
echo "------------------------------------------------------------"
