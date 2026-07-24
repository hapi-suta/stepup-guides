#!/usr/bin/env bash
# DESC: Removes the less package so the command is unavailable
# =============================================================================
# SCENARIO 06 - Missing Command (less removed)
# Removes the less package. The candidate must figure out the package is missing
# and reinstall it.
# =============================================================================

set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-06-state.env"

header "Injecting Chaos: Missing Command (less)"

# ---------- confirm connectivity ----------
step "Verifying SSH connectivity to NODE1"
if ! remote_exec "$NODE1" "echo ok" >/dev/null 2>&1; then
  error "Cannot SSH into NODE1 - aborting injection"
  exit 1
fi
info "SSH connectivity confirmed"

# ---------- save state ----------
step "Saving original state"
LESS_VERSION=$(remote_exec "$NODE1" "rpm -q less")
cat > "$STATE_FILE" <<STEOF
INJECT_TIMESTAMP=$(date +%s)
ORIG_LESS_PKG=${LESS_VERSION}
STEOF

# ---------- remove less ----------
step "Removing the less package"
remote_exec "$NODE1" "sudo dnf remove -y less" >/dev/null 2>&1

# ---------- verify injection ----------
step "Verifying less is no longer available"
if remote_exec "$NODE1" "which less" >/dev/null 2>&1; then
  error "less is still available - injection failed"
  exit 1
fi
info "less has been removed"

# ---------- print alert ----------
echo ""
echo "============================================================"
echo "  ALERT: less: command not found when reading logs"
echo "  Cannot use 'less' to page through log files."
echo "  The command appears to be missing from the system."
echo "============================================================"
echo ""
info "State saved to ${STATE_FILE}"
info "Candidate should diagnose and reinstall the missing command."
