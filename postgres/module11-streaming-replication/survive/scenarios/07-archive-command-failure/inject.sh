#!/usr/bin/env bash
# Scenario 07 - Archive Command Failure: Break WAL archiving by revoking archive directory permissions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-07-state.env"

header "Scenario 07 - Archive Command Failure"

# ---------- discover topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
STANDBY=$(get_standby)
if [[ -z "$PRIMARY" || -z "$STANDBY" ]]; then
  error "Need both a running primary and standby. Aborting."
  exit 1
fi
info "Primary: $PRIMARY | Standby: $STANDBY"

# ---------- get archive directory ----------
step "Locating archive directory on primary..."
ARCHIVE_CMD=$(remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SHOW archive_command\"")
info "Current archive_command: $ARCHIVE_CMD"

# Extract the archive directory from the archive_command
ARCHIVE_DIR=$(echo "$ARCHIVE_CMD" | grep -oP '(?<=cp %p )\S+' | sed 's|/%f.*||' || echo "/var/lib/pgsql/16/archive")
info "Archive directory: $ARCHIVE_DIR"

# ---------- capture baseline archive stats ----------
step "Capturing baseline archive stats..."
BASELINE_FAILED=$(remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SELECT failed_count FROM pg_stat_archiver\"" | tr -d '[:space:]')
info "Baseline failed_count: $BASELINE_FAILED"

# ---------- break archive permissions ----------
step "Revoking permissions on archive directory ($ARCHIVE_DIR)..."
remote_exec "$PRIMARY" "sudo chmod 000 '${ARCHIVE_DIR}'"
success "Archive directory permissions set to 000."

# ---------- generate WAL to trigger archiving ----------
step "Generating WAL to trigger archive failures..."
pg_exec "$PRIMARY" \
  "INSERT INTO employees(name, department) SELECT 'archive_' || g, 'chaos' FROM generate_series(1,200) g"
remote_exec "$PRIMARY" "sudo -u postgres psql -p ${PG_PORT} -c 'SELECT pg_switch_wal()'"
sleep 3
remote_exec "$PRIMARY" "sudo -u postgres psql -p ${PG_PORT} -c 'SELECT pg_switch_wal()'"
sleep 3

# ---------- check failures started ----------
step "Verifying archive failures are occurring..."
INJECT_FAILED=$(remote_exec "$PRIMARY" \
  "sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SELECT failed_count FROM pg_stat_archiver\"" | tr -d '[:space:]')
info "Current failed_count: $INJECT_FAILED"

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="07-archive-command-failure"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
ARCHIVE_DIR="$ARCHIVE_DIR"
ARCHIVE_CMD="$ARCHIVE_CMD"
BASELINE_FAILED="$BASELINE_FAILED"
INJECT_FAILED="$INJECT_FAILED"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: WAL archiving is FAILING on primary ($PRIMARY)."
echo "pg_stat_archiver shows $INJECT_FAILED failures (was $BASELINE_FAILED)."
echo "Archive directory: $ARCHIVE_DIR"
echo "Diagnose the issue, fix it, and verify archiving resumes."
echo "------------------------------------------------------------"
