#!/usr/bin/env bash
# Scenario 03 - WAL Corruption: Rename a WAL segment on the standby.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-03-state.env"

header "Scenario 03 - WAL Corruption"

# ---------- discover topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
STANDBY=$(get_standby)
if [[ -z "$PRIMARY" || -z "$STANDBY" ]]; then
  error "Need both a running primary and standby. Aborting."
  exit 1
fi
info "Primary: $PRIMARY | Standby: $STANDBY"

# ---------- locate WAL directory on standby ----------
step "Locating WAL directory on standby..."
WAL_DIR=$(remote_exec "$STANDBY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SHOW data_directory\"")
WAL_DIR="${WAL_DIR}/pg_wal"
info "WAL directory: $WAL_DIR"

# ---------- pick a WAL file to corrupt ----------
step "Selecting WAL file to rename..."
WAL_FILE=$(ssh $SSH_OPTS "${SSH_USER}@${STANDBY}" \
  "sudo -iu postgres bash -c 'ls -1t ${WAL_DIR}/0000000* 2>/dev/null | head -1'")

if [[ -z "$WAL_FILE" ]]; then
  error "No WAL files found on standby. Aborting."
  exit 1
fi

WAL_BASENAME=$(basename "$WAL_FILE")
info "Target WAL file: $WAL_BASENAME"

# ---------- rename the WAL file ----------
step "Renaming WAL file to break replay..."
remote_exec "$STANDBY" \
  "sudo -u postgres mv '${WAL_DIR}/${WAL_BASENAME}' '${WAL_DIR}/${WAL_BASENAME}.corrupt'"

success "WAL file renamed: ${WAL_BASENAME} -> ${WAL_BASENAME}.corrupt"

# ---------- force standby to notice ----------
step "Restarting standby to trigger WAL replay failure..."
remote_exec "$STANDBY" "sudo systemctl restart postgresql-16" || true

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="03-wal-corruption"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
WAL_DIR="$WAL_DIR"
WAL_FILE="$WAL_BASENAME"
CORRUPT_FILE="${WAL_BASENAME}.corrupt"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: WAL replay failure on standby ($STANDBY)."
echo "WAL segment ${WAL_BASENAME} is missing from pg_wal."
echo "Standby may be stuck or crashing. Investigate the PG log"
echo "and restore streaming replication."
echo "------------------------------------------------------------"
