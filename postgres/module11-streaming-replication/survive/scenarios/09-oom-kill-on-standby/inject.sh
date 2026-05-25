#!/usr/bin/env bash
# Scenario 09 - OOM Kill on Standby: SIGKILL the postgres process to simulate OOM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-09-state.env"

header "Scenario 09 - OOM Kill on Standby"

# ---------- discover topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
STANDBY=$(get_standby)
if [[ -z "$PRIMARY" || -z "$STANDBY" ]]; then
  error "Need both a running primary and standby. Aborting."
  exit 1
fi
info "Primary: $PRIMARY | Standby: $STANDBY"

# ---------- capture pre-kill state ----------
step "Capturing pre-kill state..."
REPL_STATE=$(pg_exec "$PRIMARY" \
  "SELECT state FROM pg_stat_replication LIMIT 1" 2>/dev/null || echo "")
LSN=$(pg_exec "$PRIMARY" "SELECT pg_current_wal_lsn()" 2>/dev/null || echo "")
info "Replication state: $REPL_STATE"
info "Current WAL LSN: $LSN"

# ---------- get the postmaster PID on standby ----------
step "Finding postmaster PID on standby..."
POSTMASTER_PID=$(remote_exec "$STANDBY" \
  "sudo -u postgres head -1 /var/lib/pgsql/16/data/postmaster.pid" 2>/dev/null | tr -d '[:space:]')
info "Postmaster PID: $POSTMASTER_PID"

# ---------- plant a fake OOM message in syslog ----------
step "Planting OOM-style message in syslog..."
remote_exec "$STANDBY" \
  "echo 'Out of memory: Killed process ${POSTMASTER_PID} (postgres) total-vm:2048000kB' | sudo tee -a /var/log/messages > /dev/null" 2>/dev/null || \
remote_exec "$STANDBY" \
  "echo 'Out of memory: Killed process ${POSTMASTER_PID} (postgres) total-vm:2048000kB' | sudo tee -a /var/log/messages > /dev/null" 2>/dev/null || true

# ---------- SIGKILL the postmaster ----------
step "Sending SIGKILL to postmaster on standby (simulating OOM kill)..."
remote_exec "$STANDBY" "sudo kill -9 ${POSTMASTER_PID}" 2>/dev/null || true

# Wait for process to die
sleep 3

# Verify it is down
PG_RUNNING=$(remote_exec "$STANDBY" \
  "sudo -u postgres pg_isready -p ${PG_PORT} 2>/dev/null && echo yes || echo no" | tr -d '[:space:]')
info "PostgreSQL running after kill: $PG_RUNNING"

# ---------- write some data on primary to create lag ----------
step "Writing data on primary to create replication gap..."
pg_exec "$PRIMARY" \
  "INSERT INTO employees(name, department) SELECT 'oom_' || g, 'chaos' FROM generate_series(1,500) g"
info "Inserted 500 rows on primary while standby is down."

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="09-oom-kill-on-standby"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
PRE_KILL_LSN="$LSN"
KILLED_PID="$POSTMASTER_PID"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: PostgreSQL on standby ($STANDBY) has crashed."
echo "Process was killed with SIGKILL (simulated OOM)."
echo "Replication has stopped. Primary ($PRIMARY) is still running"
echo "and accepting writes."
echo "Investigate the crash, restart PostgreSQL on the standby,"
echo "and verify replication catches up."
echo "------------------------------------------------------------"
