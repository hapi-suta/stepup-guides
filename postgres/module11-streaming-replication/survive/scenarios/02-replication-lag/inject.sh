#!/usr/bin/env bash
# Scenario 02 - Replication Lag: Generate heavy write load to create lag.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-02-state.env"

header "Scenario 02 - Replication Lag"

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
BASELINE_LAG=$(pg_exec "$PRIMARY" \
  "SELECT coalesce(pg_wal_lsn_diff(sent_lsn, replay_lsn)::bigint, 0) FROM pg_stat_replication LIMIT 1")
info "Baseline lag: ${BASELINE_LAG} bytes"

# ---------- generate write load ----------
step "Generating heavy write load on primary..."

# Create a load table and blast inserts via pgbench custom script
remote_exec "$PRIMARY" "sudo -u postgres psql -p ${PG_PORT} -d ${PG_DB} -c \"
  CREATE TABLE IF NOT EXISTS chaos_load (
    id serial PRIMARY KEY,
    payload text,
    created_at timestamptz DEFAULT now()
  );
\""

# Write pgbench script to file, then run it (process substitution fails over SSH)
remote_exec "$PRIMARY" "echo \"INSERT INTO chaos_load(payload) VALUES (repeat('x', 8000));\" > ${CHAOS_STATE_DIR:-/tmp}/stepup-pgbench.sql"
remote_exec "$PRIMARY" "nohup sudo -u postgres pgbench \
  -p ${PG_PORT} -d ${PG_DB} -c 4 -j 2 -T 20 \
  -f ${CHAOS_STATE_DIR:-/tmp}/stepup-pgbench.sql \
  > ${CHAOS_STATE_DIR:-/tmp}/stepup-pgbench.log 2>&1 &"

info "pgbench load running in background (20s, 4 clients)"

# Give it a few seconds to build up lag
sleep 3

# Capture current lag
INJECT_LAG=$(pg_exec "$PRIMARY" \
  "SELECT coalesce(pg_wal_lsn_diff(sent_lsn, replay_lsn)::bigint, 0) FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "0")

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="02-replication-lag"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
BASELINE_LAG="$BASELINE_LAG"
INJECT_LAG="$INJECT_LAG"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: Replication lag detected on standby ($STANDBY)."
echo "Current lag: ${INJECT_LAG} bytes (baseline was ${BASELINE_LAG})."
echo "Heavy write load is running on primary ($PRIMARY)."
echo "Diagnose the cause, stop the load, and verify catchup."
echo "------------------------------------------------------------"
