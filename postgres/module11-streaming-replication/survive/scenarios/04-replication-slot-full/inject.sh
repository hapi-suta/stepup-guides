#!/usr/bin/env bash
# Scenario 04 - Replication Slot Full: Pause the standby while writes flood the primary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-04-state.env"

header "Scenario 04 - Replication Slot Full"

# ---------- discover topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
STANDBY=$(get_standby)
if [[ -z "$PRIMARY" || -z "$STANDBY" ]]; then
  error "Need both a running primary and standby. Aborting."
  exit 1
fi
info "Primary: $PRIMARY | Standby: $STANDBY"

# ---------- capture baseline disk usage ----------
step "Capturing baseline disk usage on primary..."
DATA_DIR=$(remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SHOW data_directory\"")
WAL_DIR="${DATA_DIR}/pg_wal"

BASELINE_DISK=$(remote_exec "$PRIMARY" \
  "sudo du -sm '${WAL_DIR}' | awk '{print \$1}'" | tr -d '[:space:]')
info "Baseline WAL directory size: ${BASELINE_DISK} MB"

# ---------- stop the standby to stall the slot ----------
step "Stopping PostgreSQL on standby ($STANDBY) to stall replication slot..."
remote_exec "$STANDBY" "sudo systemctl stop postgresql-16"
info "Standby stopped. Replication slot will begin retaining WAL."

# ---------- generate heavy write load ----------
step "Generating heavy write load on primary..."
remote_exec "$PRIMARY" "sudo -u postgres psql -p ${PG_PORT} -d ${PG_DB} -c \"
  CREATE TABLE IF NOT EXISTS chaos_load (
    id serial PRIMARY KEY,
    payload text,
    created_at timestamptz DEFAULT now()
  );
\""

remote_exec "$PRIMARY" "echo \"INSERT INTO chaos_load(payload) VALUES (repeat('x', 8000));\" > ${CHAOS_STATE_DIR:-/tmp}/stepup-pgbench.sql"
remote_exec "$PRIMARY" "nohup sudo -u postgres pgbench \
  -p ${PG_PORT} -d ${PG_DB} -c 4 -j 2 -T 30 \
  -f ${CHAOS_STATE_DIR:-/tmp}/stepup-pgbench.sql \
  > ${CHAOS_STATE_DIR:-/tmp}/stepup-pgbench.log 2>&1 &"

info "pgbench load running in background (30s, 4 clients)"

# Give it a moment to generate WAL
sleep 5

# Check new disk usage
INJECT_DISK=$(remote_exec "$PRIMARY" \
  "sudo du -sm '${WAL_DIR}' | awk '{print \$1}'" | tr -d '[:space:]')
info "WAL directory size after injection: ${INJECT_DISK} MB"

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="04-replication-slot-full"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
WAL_DIR="$WAL_DIR"
BASELINE_DISK="$BASELINE_DISK"
INJECT_DISK="$INJECT_DISK"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: Standby ($STANDBY) is DOWN and the replication slot"
echo "is retaining WAL on the primary ($PRIMARY)."
echo "WAL directory is growing: ${BASELINE_DISK} MB -> ${INJECT_DISK} MB."
echo "Disk exhaustion is imminent if not addressed."
echo "Diagnose, recover the standby, and verify WAL retention stops."
echo "------------------------------------------------------------"
