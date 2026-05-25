#!/usr/bin/env bash
# Scenario 05 - Standby Won't Start: Corrupt standby config and remove standby.signal.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-05-state.env"

header "Scenario 05 - Standby Won't Start"

# ---------- discover topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
STANDBY=$(get_standby)
if [[ -z "$PRIMARY" || -z "$STANDBY" ]]; then
  error "Need both a running primary and standby. Aborting."
  exit 1
fi
info "Primary: $PRIMARY | Standby: $STANDBY"

# ---------- get data directory ----------
step "Locating data directory on standby..."
DATA_DIR=$(remote_exec "$STANDBY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SHOW data_directory\"")
info "Data directory: $DATA_DIR"

# ---------- backup original config ----------
step "Backing up original postgresql.auto.conf..."
remote_exec "$STANDBY" \
  "sudo -u postgres cp '${DATA_DIR}/postgresql.auto.conf' '${DATA_DIR}/postgresql.auto.conf.bak'"

# ---------- capture original primary_conninfo ----------
ORIGINAL_CONNINFO=$(remote_exec "$STANDBY" \
  "sudo -u postgres grep primary_conninfo '${DATA_DIR}/postgresql.auto.conf'" 2>/dev/null || echo "")
info "Original conninfo backed up"

# ---------- stop the standby ----------
step "Stopping PostgreSQL on standby..."
remote_exec "$STANDBY" "sudo systemctl stop postgresql-16"

# ---------- corrupt postgresql.auto.conf ----------
step "Corrupting primary_conninfo in postgresql.auto.conf..."
remote_exec "$STANDBY" \
  "sudo -u postgres sed -i \"s/primary_conninfo.*/primary_conninfo = 'host=999.999.999.999 port=9999 user=nobody dbname=nonexistent'/\" '${DATA_DIR}/postgresql.auto.conf'"

# ---------- remove standby.signal ----------
step "Removing standby.signal..."
remote_exec "$STANDBY" \
  "sudo -u postgres mv '${DATA_DIR}/standby.signal' '${DATA_DIR}/standby.signal.bak'"

success "standby.signal removed and primary_conninfo corrupted"

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="05-standby-wont-start"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
DATA_DIR="$DATA_DIR"
ORIGINAL_CONNINFO="$ORIGINAL_CONNINFO"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: PostgreSQL standby ($STANDBY) is DOWN and will not"
echo "start correctly as a standby. Configuration has been altered."
echo "Check the logs, fix the configuration, and restore streaming"
echo "replication."
echo "------------------------------------------------------------"
