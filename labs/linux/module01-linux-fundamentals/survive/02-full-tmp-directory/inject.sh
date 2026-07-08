#!/usr/bin/env bash
# DESC: Fills /tmp with large files until 95%+ full
# =============================================================================
# SCENARIO 02 - Full /tmp Directory
# Creates large files in /tmp to fill the partition. The candidate must find
# and remove the large files to free space.
# =============================================================================

set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-02-state.env"

header "Injecting Chaos: Full /tmp Directory"

# ---------- confirm connectivity ----------
step "Verifying SSH connectivity to NODE1"
if ! remote_exec "$NODE1" "echo ok" >/dev/null 2>&1; then
  error "Cannot SSH into NODE1 - aborting injection"
  exit 1
fi
info "SSH connectivity confirmed"

# ---------- save state ----------
step "Saving original /tmp usage"
ORIG_USAGE=$(remote_exec "$NODE1" "df /tmp --output=pcent | tail -1 | tr -d ' %'")
cat > "$STATE_FILE" <<STEOF
INJECT_TIMESTAMP=$(date +%s)
ORIG_TMP_USAGE=${ORIG_USAGE}
STEOF

# ---------- fill /tmp ----------
step "Creating large files in /tmp"

# Get available space in /tmp in MB and fill most of it
remote_exec "$NODE1" "
  AVAIL_KB=\$(df /tmp --output=avail | tail -1 | tr -d ' ')
  FILL_KB=\$(( AVAIL_KB * 90 / 100 ))
  FILL_MB=\$(( FILL_KB / 1024 ))

  # Create several large files to simulate real-world clutter
  CHUNK=\$(( FILL_MB / 4 ))
  sudo dd if=/dev/zero of=/tmp/chaos-bigfile-01.dat bs=1M count=\${CHUNK} 2>/dev/null
  sudo dd if=/dev/zero of=/tmp/chaos-bigfile-02.dat bs=1M count=\${CHUNK} 2>/dev/null
  sudo dd if=/dev/zero of=/tmp/chaos-bigfile-03.dat bs=1M count=\${CHUNK} 2>/dev/null
  sudo dd if=/dev/zero of=/tmp/chaos-old-sort-result.tmp bs=1M count=\${CHUNK} 2>/dev/null
"

# ---------- verify injection ----------
step "Verifying /tmp usage"
CURRENT_USAGE=$(remote_exec "$NODE1" "df /tmp --output=pcent | tail -1 | tr -d ' %'")
info "/tmp usage is now ${CURRENT_USAGE}%"

if (( CURRENT_USAGE < 80 )); then
  warn "/tmp usage is only ${CURRENT_USAGE}% - may not trigger the expected symptoms"
fi

# ---------- print alert ----------
echo ""
echo "============================================================"
echo "  ALERT: Application cannot create temporary files"
echo "  /tmp partition is nearly full."
echo "  Database sort operations and temp table creation may fail."
echo "============================================================"
echo ""
info "State saved to ${STATE_FILE}"
info "Candidate should diagnose and free space in /tmp."
