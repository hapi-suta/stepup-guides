#!/usr/bin/env bash
# DESC: Sets /etc/hosts to permission 000 so it cannot be read
# =============================================================================
# SCENARIO 03 - Wrong File Permissions
# Removes all permissions from /etc/hosts. The candidate must diagnose the
# permission problem and restore correct permissions.
# =============================================================================

set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-03-state.env"

header "Injecting Chaos: Wrong File Permissions"

# ---------- confirm connectivity ----------
step "Verifying SSH connectivity to NODE1"
if ! remote_exec "$NODE1" "echo ok" >/dev/null 2>&1; then
  error "Cannot SSH into NODE1 - aborting injection"
  exit 1
fi
info "SSH connectivity confirmed"

# ---------- save state ----------
step "Saving original permissions"
ORIG_PERMS=$(remote_exec "$NODE1" "stat -c '%a' /etc/hosts")
ORIG_OWNER=$(remote_exec "$NODE1" "stat -c '%U:%G' /etc/hosts")
cat > "$STATE_FILE" <<STEOF
INJECT_TIMESTAMP=$(date +%s)
ORIG_PERMS=${ORIG_PERMS}
ORIG_OWNER=${ORIG_OWNER}
STEOF

# ---------- break permissions ----------
step "Setting /etc/hosts to permission 000"
remote_exec "$NODE1" "sudo chmod 000 /etc/hosts"

# ---------- verify injection ----------
step "Verifying /etc/hosts is unreadable"
if remote_exec "$NODE1" "cat /etc/hosts" >/dev/null 2>&1; then
  warn "/etc/hosts is still readable (ec2-user may have sudo cached)"
fi

# ---------- print alert ----------
echo ""
echo "============================================================"
echo "  ALERT: DNS resolution is failing for local hostnames"
echo "  Applications cannot resolve hostnames to IP addresses."
echo "  The /etc/hosts file may be corrupted or inaccessible."
echo "============================================================"
echo ""
info "State saved to ${STATE_FILE}"
info "Candidate should diagnose and fix the file permissions."
