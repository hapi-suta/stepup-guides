#!/usr/bin/env bash
# DESC: Hides grep by moving it out of PATH
# =============================================================================
# SCENARIO 01 - Missing PATH (grep hidden)
# Moves /usr/bin/grep to /usr/bin/grep.hidden so the command cannot be found.
# The candidate must understand PATH and restore the command.
# =============================================================================

set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-01-state.env"

header "Injecting Chaos: Missing PATH (grep hidden)"

# ---------- confirm connectivity ----------
step "Verifying SSH connectivity to NODE1"
if ! remote_exec "$NODE1" "echo ok" >/dev/null 2>&1; then
  error "Cannot SSH into NODE1 - aborting injection"
  exit 1
fi
info "SSH connectivity confirmed"

# ---------- save state ----------
step "Saving original state"
ORIG_GREP_PATH=$(remote_exec "$NODE1" "which grep")
cat > "$STATE_FILE" <<STEOF
INJECT_TIMESTAMP=$(date +%s)
ORIG_GREP_PATH=${ORIG_GREP_PATH}
STEOF

# ---------- hide grep ----------
step "Moving grep to grep.hidden"
remote_exec "$NODE1" "sudo mv /usr/bin/grep /usr/bin/grep.hidden"

# ---------- verify injection ----------
step "Verifying grep is no longer available"
if remote_exec "$NODE1" "which grep" >/dev/null 2>&1; then
  error "grep is still available - injection failed"
  exit 1
fi

# ---------- print alert ----------
echo ""
echo "============================================================"
echo "  ALERT: grep: command not found when searching logs"
echo "  Cannot search database logs or configuration files."
echo "  The grep command is missing from the system."
echo "============================================================"
echo ""
info "State saved to ${STATE_FILE}"
info "Candidate should diagnose and resolve the missing command."
