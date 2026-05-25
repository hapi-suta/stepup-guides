#!/usr/bin/env bash
# Scenario 10 - Disk Full on Primary: Fill the WAL partition with a large
# temp file, causing WAL write failures on the primary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/stepup-repmgr-10-state.env"

header "Scenario 10 - Disk Full on Primary"

# ---------- discover current topology ----------
step "Discovering current topology..."
PRIMARY=$(get_primary)
if [[ -z "$PRIMARY" ]]; then
  error "Could not find a running primary. Aborting injection."
  exit 1
fi
info "Current primary: $PRIMARY"

STANDBYS=$(get_standbys)
info "Current standbys: $(echo "$STANDBYS" | tr '\n' ' ')"

# ---------- capture pre-fill state ----------
step "Capturing pre-fill state..."
TIMELINE=$(pg_exec "$PRIMARY" "SELECT timeline_id FROM pg_control_checkpoint()")
ROW_COUNT=$(pg_exec "$PRIMARY" "SELECT count(*) FROM employees")
DISK_USAGE_BEFORE=$(remote_exec "$PRIMARY" \
  "df -h ${PG_DATA}/pg_wal | tail -1 | awk '{print \$5}'")

cat > "$STATE_FILE" <<EOF
SCENARIO="10-disk-full-on-primary"
INJECTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORIGINAL_PRIMARY="$PRIMARY"
ORIGINAL_STANDBYS="$(echo "$STANDBYS" | tr '\n' ',')"
PRE_FILL_TIMELINE="$TIMELINE"
PRE_FILL_ROW_COUNT="$ROW_COUNT"
DISK_USAGE_BEFORE="$DISK_USAGE_BEFORE"
EOF

info "State saved to $STATE_FILE"
info "Disk usage before fill: $DISK_USAGE_BEFORE"

# ---------- determine how much space to fill ----------
# Get available space in MB on the WAL partition, then fill most of it
step "Calculating fill size..."
AVAIL_KB=$(remote_exec "$PRIMARY" \
  "df -k ${PG_DATA}/pg_wal | tail -1 | awk '{print \$4}'")
AVAIL_KB=$(echo "$AVAIL_KB" | tr -d '[:space:]')

# Leave only 10MB free - fill the rest
FILL_MB=$(( (AVAIL_KB / 1024) - 10 ))

if [[ "$FILL_MB" -lt 50 ]]; then
  warn "Only ${FILL_MB}MB available to fill. Disk might already be near full."
  FILL_MB=50
fi

if [[ "$FILL_MB" -gt 2000 ]]; then
  # Cap at 2GB to avoid overly long dd operations
  FILL_MB=2000
fi

info "Will fill ${FILL_MB}MB on WAL partition"

# ---------- fill the disk ----------
step "Creating fill file on WAL partition (${FILL_MB}MB)..."
remote_exec "$PRIMARY" \
  "dd if=/dev/zero of=${PG_DATA}/pg_wal/FILL_DISK_CHAOS \
   bs=1M count=${FILL_MB} 2>/dev/null" || true

DISK_USAGE_AFTER=$(remote_exec "$PRIMARY" \
  "df -h ${PG_DATA}/pg_wal | tail -1 | awk '{print \$5}'")

success "Disk filled. Usage now: $DISK_USAGE_AFTER"

# ---------- try to trigger WAL write failure ----------
step "Attempting writes to trigger WAL failures..."
pg_exec "$PRIMARY" \
  "INSERT INTO employees(name, department) SELECT 'disk_fill_' || g, 'chaos' FROM generate_series(1,100) g" 2>/dev/null || true

# ---------- print alert message ----------
echo ""
echo "------------------------------------------------------------"
echo "ALERT: DISK FULL ON PRIMARY!"
echo ""
echo "The WAL partition on primary ($PRIMARY) is almost full."
echo "Disk usage: $DISK_USAGE_AFTER"
echo ""
echo "A large fill file was created at:"
echo "  ${PG_DATA}/pg_wal/FILL_DISK_CHAOS"
echo ""
echo "PostgreSQL may be failing WAL writes, which means:"
echo "  - New transactions may fail or hang"
echo "  - WAL archiving may fail"
echo "  - Replication may fall behind or disconnect"
echo ""
echo "Your tasks:"
echo "  1. Identify disk usage (df -h)"
echo "  2. Find the offending file in pg_wal"
echo "  3. Remove it and verify space is freed"
echo "  4. Check if PostgreSQL needs a restart"
echo "  5. Verify WAL writes resume and replication catches up"
echo "  6. Run validate.sh"
echo "------------------------------------------------------------"
