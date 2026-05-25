#!/usr/bin/env bash
# Scenario 06 - Timeline Divergence: Force two nodes onto different timelines.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="${CHAOS_STATE_DIR:-/tmp}/stepup-06-state.env"

header "Scenario 06 - Timeline Divergence"

# ---------- discover topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
STANDBY=$(get_standby)
if [[ -z "$PRIMARY" || -z "$STANDBY" ]]; then
  error "Need both a running primary and standby. Aborting."
  exit 1
fi
info "Primary: $PRIMARY | Standby: $STANDBY"

# ---------- capture baseline timeline ----------
ORIG_TIMELINE=$(pg_exec "$PRIMARY" \
  "SELECT timeline_id FROM pg_control_checkpoint()")
info "Original timeline: $ORIG_TIMELINE"

# ---------- stop the standby ----------
step "Stopping standby ($STANDBY) to isolate it..."
remote_exec "$STANDBY" "sudo systemctl stop postgresql-16"
info "Standby stopped."

# ---------- write data on the primary to advance WAL ----------
step "Writing data on primary to advance WAL..."
pg_exec "$PRIMARY" \
  "INSERT INTO employees(name, department) SELECT 'diverge_' || g, 'chaos' FROM generate_series(1,500) g"
info "Inserted 500 rows on primary."

# ---------- promote the standby to create timeline fork ----------
# First, restart the standby briefly so we can promote it
step "Restarting standby briefly to promote it..."
remote_exec "$STANDBY" "sudo systemctl start postgresql-16"
sleep 3

# Promote the standby - this creates a new timeline
step "Promoting standby to create timeline divergence..."
remote_exec "$STANDBY" \
  "sudo -u postgres /usr/pgsql-16/bin/pg_ctl promote -D /var/lib/pgsql/16/data"
sleep 3

# Write data on the promoted standby (now a second primary)
step "Writing data on promoted node to cement divergence..."
pg_exec "$STANDBY" \
  "INSERT INTO employees(name, department) SELECT 'promoted_' || g, 'chaos' FROM generate_series(1,200) g"
info "Inserted 200 rows on promoted node."

# ---------- get new timelines ----------
TL_NODE1=$(pg_exec "$PRIMARY" \
  "SELECT timeline_id FROM pg_control_checkpoint()" 2>/dev/null || echo "unknown")
TL_NODE2=$(pg_exec "$STANDBY" \
  "SELECT timeline_id FROM pg_control_checkpoint()" 2>/dev/null || echo "unknown")

# ---------- stop both nodes ----------
step "Stopping both nodes..."
remote_exec "$PRIMARY" "sudo systemctl stop postgresql-16"
remote_exec "$STANDBY" "sudo systemctl stop postgresql-16"

# ---------- save state ----------
cat > "$STATE_FILE" <<EOF
SCENARIO="06-timeline-divergence"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRIMARY="$PRIMARY"
STANDBY="$STANDBY"
ORIG_TIMELINE="$ORIG_TIMELINE"
TL_NODE1="$TL_NODE1"
TL_NODE2="$TL_NODE2"
EOF

info "State saved to $STATE_FILE"

# ---------- print alert ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: Timeline divergence detected."
echo "Node1 ($PRIMARY) is on timeline $TL_NODE1."
echo "Node2 ($STANDBY) is on timeline $TL_NODE2."
echo "Both nodes are STOPPED. Neither is streaming."
echo "Use pg_rewind or pg_basebackup to bring one node back as a"
echo "standby, start the other as primary, and restore replication."
echo "------------------------------------------------------------"
