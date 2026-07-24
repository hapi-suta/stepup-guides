#!/usr/bin/env bash
# DESC: Creates a large file in /var to consume disk space
# =============================================================================
# SCENARIO 07 - Disk Space Low
# Creates a 1GB file in /var to fill the partition. The candidate must find
# the large file using df, du, and find, then remove it.
# =============================================================================

set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-07-state.env"

header "Injecting Chaos: Disk Space Low"

# ---------- confirm connectivity ----------
step "Verifying SSH connectivity to NODE1"
if ! remote_exec "$NODE1" "echo ok" >/dev/null 2>&1; then
  error "Cannot SSH into NODE1 - aborting injection"
  exit 1
fi
info "SSH connectivity confirmed"

# ---------- save state ----------
step "Saving original disk usage"
ORIG_USAGE=$(remote_exec "$NODE1" "df /var --output=pcent | tail -1 | tr -d ' %'")
cat > "$STATE_FILE" <<STEOF
INJECT_TIMESTAMP=$(date +%s)
ORIG_VAR_USAGE=${ORIG_USAGE}
STEOF

# ---------- create large file ----------
step "Creating 1GB file in /var"
remote_exec "$NODE1" "sudo dd if=/dev/zero of=/var/chaos-old-backup-full.dump bs=1M count=1024 2>/dev/null"

# Also create a few smaller decoy files
step "Creating additional files to simulate real clutter"
remote_exec "$NODE1" "
  sudo dd if=/dev/zero of=/var/log/chaos-old-audit.log.1 bs=1M count=50 2>/dev/null
  sudo dd if=/dev/zero of=/var/log/chaos-old-audit.log.2 bs=1M count=50 2>/dev/null
"

# ---------- verify injection ----------
step "Verifying disk usage increased"
NEW_USAGE=$(remote_exec "$NODE1" "df /var --output=pcent | tail -1 | tr -d ' %'")
info "/var usage went from ${ORIG_USAGE}% to ${NEW_USAGE}%"

# ---------- print alert ----------
echo ""
echo "============================================================"
echo "  ALERT: Low disk space warning on /var partition"
echo "  Current usage: ${NEW_USAGE}%"
echo "  Database operations may fail if disk becomes full."
echo "  Investigate and free space immediately."
echo "============================================================"
echo ""
info "State saved to ${STATE_FILE}"
info "Candidate should find and remove the files consuming space."
