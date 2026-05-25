#!/usr/bin/env bash
# Scenario 08 - pg_hba Lockout: Remove replication entry from pg_hba.conf, breaking standby connection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-08-state.env"

header "Scenario 08 - pg_hba Lockout"

# ---------- discover topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
STANDBY=$(get_standby)
if [[ -z "$PRIMARY" || -z "$STANDBY" ]]; then
  error "Need both a running primary and standby. Aborting."
  exit 1
fi
info "Primary: $PRIMARY | Standby: $STANDBY"

# ---------- locate pg_hba.conf ----------
step "Locating pg_hba.conf on primary..."
HBA_FILE=$(remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SHOW hba_file\"")
info "pg_hba.conf location: $HBA_FILE"

# ---------- backup original pg_hba.conf ----------
step "Backing up pg_hba.conf..."
remote_exec "$PRIMARY" "sudo cp '${HBA_FILE}' '${HBA_FILE}.bak'"
success "Backup saved to ${HBA_FILE}.bak"

# ---------- capture original replication lines ----------
REPL_LINES=$(remote_exec "$PRIMARY" \
  "sudo grep -n 'replication' '${HBA_FILE}'" 2>/dev/null || echo "")
info "Original replication lines: $REPL_LINES"

# ---------- remove replication entries ----------
step "Removing replication entries from pg_hba.conf..."
remote_exec "$PRIMARY" \
  "sudo sed -i '/replication/d' '${HBA_FILE}'"
success "All replication lines removed from pg_hba.conf."

# ---------- reload to apply ----------
step "Reloading PostgreSQL configuration on primary..."
remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -c 'SELECT pg_reload_conf()'"
info "Configuration reloaded. Standby replication connections will be rejected."

# Wait for the standby to notice
sleep 5

# ---------- verify standby lost connection ----------
step "Checking if standby replication has dropped..."
REPL_COUNT=$(pg_exec "$PRIMARY" \
  "SELECT count(*) FROM pg_stat_replication" 2>/dev/null | tr -d '[:space:]')
info "Active replication connections on primary: $REPL_COUNT"

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="08-pg-hba-lockout"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
HBA_FILE="$HBA_FILE"
REPL_LINES="$REPL_LINES"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: Streaming replication has STOPPED."
echo "The standby ($STANDBY) can no longer connect to the"
echo "primary ($PRIMARY) for replication."
echo "Active replication connections: $REPL_COUNT"
echo "Check the standby logs and the primary's pg_hba.conf."
echo "------------------------------------------------------------"
