#!/usr/bin/env bash
# Scenario 08 - Standby Promotion Race: Kill primary, then manually promote
# TWO standbys simultaneously, creating a split-brain condition.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/stepup-repmgr-08-state.env"

header "Scenario 08 - Standby Promotion Race (Dual Promote)"

# ---------- discover current topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
if [[ -z "$PRIMARY" ]]; then
  error "Could not find a running primary. Aborting injection."
  exit 1
fi
info "Current primary: $PRIMARY"

STANDBYS=$(get_standbys)
STANDBY_A=$(echo "$STANDBYS" | head -1)
STANDBY_B=$(echo "$STANDBYS" | tail -1)
info "Current standbys: $(echo "$STANDBYS" | tr '\n' ' ')"

if [[ -z "$STANDBY_A" ]] || [[ -z "$STANDBY_B" ]] || [[ "$STANDBY_A" == "$STANDBY_B" ]]; then
  error "Need at least 2 distinct standbys. Aborting injection."
  exit 1
fi
info "Will promote both: $STANDBY_A and $STANDBY_B"

# ---------- capture pre-crash state ----------
step "Capturing pre-crash state..."
TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees")

cat > "$STATE_FILE" <<EOF
SCENARIO="08-standby-promotion-race"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
STANDBY_A="$STANDBY_A"
STANDBY_B="$STANDBY_B"
PRE_CRASH_TIMELINE="$TIMELINE"
PRE_CRASH_ROW_COUNT="$ROW_COUNT"
EOF

info "State saved to $STATE_FILE"

# ---------- stop repmgrd on all nodes ----------
step "Stopping repmgrd on ALL nodes to prevent automatic handling..."
for node in "$NODE1" "$NODE2" "$NODE3" "$NODE4"; do
  remote_exec "$node" "sudo systemctl stop ${REPMGRD_SERVICE} 2>/dev/null || sudo systemctl stop repmgrd" 2>/dev/null || true
done

success "repmgrd stopped on all nodes"

# ---------- crash the primary ----------
step "Stopping PostgreSQL on primary ($PRIMARY)..."
remote_exec "$PRIMARY" "sudo systemctl stop ${PG_SERVICE} 2>/dev/null || sudo systemctl stop postgresql"

success "Primary ($PRIMARY) is DOWN"

# ---------- promote BOTH standbys ----------
step "Promoting standby A ($STANDBY_A)..."
remote_exec "$STANDBY_A" \
  "sudo -u postgres ${PG_BIN}/pg_ctl promote \
   -D ${PG_DATA}" 2>/dev/null || true

# Brief pause to let the first promotion register
sleep 2

step "Promoting standby B ($STANDBY_B)..."
remote_exec "$STANDBY_B" \
  "sudo -u postgres ${PG_BIN}/pg_ctl promote \
   -D ${PG_DATA}" 2>/dev/null || true

success "BOTH standbys promoted via pg_ctl promote"

# ---------- write different data to each to create divergence ----------
step "Writing divergent data to both primaries..."
sleep 2

pg_exec "$STANDBY_A" \
  "INSERT INTO employees(name, department) VALUES ('written_on_A', 'node_A')" 2>/dev/null || true
pg_exec "$STANDBY_B" \
  "INSERT INTO employees(name, department) VALUES ('written_on_B', 'node_B')" 2>/dev/null || true

success "Divergent writes committed on both nodes"

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: SPLIT-BRAIN - TWO PRIMARIES DETECTED!"
echo ""
echo "Both standbys have been promoted to primary:"
echo "  - Node A ($STANDBY_A): pg_is_in_recovery() = f"
echo "  - Node B ($STANDBY_B): pg_is_in_recovery() = f"
echo ""
echo "Both nodes have accepted DIFFERENT writes."
echo "This is the most dangerous HA failure possible."
echo ""
echo "Your tasks:"
echo "  1. Detect both primaries using pg_is_in_recovery()"
echo "  2. Decide which node to KEEP as primary (check WAL position)"
echo "  3. Shut down the loser and pg_rewind it back to standby"
echo "  4. Re-register all nodes with repmgr"
echo "  5. Handle the divergent data on the demoted node"
echo "  6. Restart repmgrd and run validate.sh"
echo ""
echo "WARNING: The demoted node's divergent writes will be LOST"
echo "unless you export them before pg_rewind."
echo "------------------------------------------------------------"
