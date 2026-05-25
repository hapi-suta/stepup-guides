#!/usr/bin/env bash
# Scenario 10 - Network Flap: Block and unblock port 5432 to disrupt replication.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-10-state.env"

header "Scenario 10 - Network Flap"

# ---------- discover topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
STANDBY=$(get_standby)
if [[ -z "$PRIMARY" || -z "$STANDBY" ]]; then
  error "Need both a running primary and standby. Aborting."
  exit 1
fi
info "Primary: $PRIMARY | Standby: $STANDBY"

# ---------- capture baseline ----------
step "Capturing baseline replication state..."
REPL_STATE=$(pg_exec "$PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
info "Baseline replication state: $REPL_STATE"

# ---------- block port 5432 on standby (incoming from primary) ----------
step "Blocking port ${PG_PORT} on standby using iptables..."
remote_exec "$STANDBY" \
  "sudo iptables -A INPUT -p tcp --sport ${PG_PORT} -s ${PRIMARY} -j DROP"
remote_exec "$STANDBY" \
  "sudo iptables -A OUTPUT -p tcp --dport ${PG_PORT} -d ${PRIMARY} -j DROP"

info "iptables rules added. WAL receiver will disconnect."

# ---------- write data during the outage ----------
step "Writing data on primary during network disruption..."
pg_exec "$PRIMARY" \
  "INSERT INTO employees(name, department) SELECT 'flap_' || g, 'chaos' FROM generate_series(1,300) g"
info "Inserted 300 rows while network is blocked."

# Wait for the WAL receiver to notice the disruption
sleep 10

# ---------- check replication state during outage ----------
OUTAGE_STATE=$(pg_exec "$PRIMARY" \
  "SELECT coalesce(state, 'disconnected') FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "disconnected")
info "Replication state during outage: $OUTAGE_STATE"

# ---------- unblock after 30 seconds total ----------
step "Waiting for network disruption window (30 seconds total)..."
sleep 20

step "Removing iptables rules to restore network..."
remote_exec "$STANDBY" \
  "sudo iptables -D INPUT -p tcp --sport ${PG_PORT} -s ${PRIMARY} -j DROP" 2>/dev/null || true
remote_exec "$STANDBY" \
  "sudo iptables -D OUTPUT -p tcp --dport ${PG_PORT} -d ${PRIMARY} -j DROP" 2>/dev/null || true

info "iptables rules removed. Network restored."

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="10-network-flap"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
OUTAGE_STATE="$OUTAGE_STATE"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: Network flap detected between primary ($PRIMARY)"
echo "and standby ($STANDBY)."
echo "Port ${PG_PORT} was blocked for 30 seconds and has been"
echo "restored. Replication may or may not have auto-recovered."
echo "Verify replication status, check for lag, and confirm"
echo "no dangling iptables rules remain."
echo "------------------------------------------------------------"
