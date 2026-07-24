#!/usr/bin/env bash
# DESC: Mounts /opt as read-only using a bind mount override
# =============================================================================
# SCENARIO 05 - Read-Only Filesystem
# Creates a read-only bind mount over /opt so files cannot be written there.
# The candidate must diagnose the mount issue and remount as read-write.
# =============================================================================

set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-05-state.env"

header "Injecting Chaos: Read-Only Filesystem"

# ---------- confirm connectivity ----------
step "Verifying SSH connectivity to NODE1"
if ! remote_exec "$NODE1" "echo ok" >/dev/null 2>&1; then
  error "Cannot SSH into NODE1 - aborting injection"
  exit 1
fi
info "SSH connectivity confirmed"

# ---------- save state ----------
step "Saving original state"
cat > "$STATE_FILE" <<STEOF
INJECT_TIMESTAMP=$(date +%s)
STEOF

# ---------- make /opt read-only ----------
step "Creating read-only bind mount on /opt"
remote_exec "$NODE1" "
  sudo mount --bind /opt /opt
  sudo mount -o remount,ro,bind /opt
"

# ---------- verify injection ----------
step "Verifying /opt is read-only"
if remote_exec "$NODE1" "sudo touch /opt/test-write-$$" 2>/dev/null; then
  remote_exec "$NODE1" "sudo rm -f /opt/test-write-$$" 2>/dev/null
  error "/opt is still writable - injection failed"
  exit 1
fi
info "/opt is now read-only"

# ---------- print alert ----------
echo ""
echo "============================================================"
echo "  ALERT: Cannot write to /opt directory"
echo "  Attempts to create files or directories in /opt fail with"
echo "  'Read-only file system' error."
echo "  Database installation and updates cannot proceed."
echo "============================================================"
echo ""
info "State saved to ${STATE_FILE}"
info "Candidate should diagnose and fix the read-only mount."
