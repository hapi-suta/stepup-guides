#!/usr/bin/env bash
# DESC: Renames the ec2-user home directory
# =============================================================================
# SCENARIO 04 - Broken Home Directory
# Renames /home/ec2-user to /home/ec2-user.broken so the user's home directory
# does not match what /etc/passwd expects. The candidate must find and restore it.
# =============================================================================

set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-04-state.env"

header "Injecting Chaos: Broken Home Directory"

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
ORIG_HOME=/home/ec2-user
STEOF

# ---------- rename home directory ----------
step "Renaming home directory"
remote_exec "$NODE1" "sudo mv /home/ec2-user /home/ec2-user.broken"

# ---------- create a minimal home so SSH still works ----------
step "Creating minimal home for SSH access"
remote_exec "$NODE1" "
  sudo mkdir -p /home/ec2-user/.ssh
  sudo cp /home/ec2-user.broken/.ssh/authorized_keys /home/ec2-user/.ssh/
  sudo chown -R ec2-user:ec2-user /home/ec2-user
  sudo chmod 700 /home/ec2-user
  sudo chmod 700 /home/ec2-user/.ssh
  sudo chmod 600 /home/ec2-user/.ssh/authorized_keys
"

# ---------- verify injection ----------
step "Verifying home directory is broken"
remote_exec "$NODE1" "test -d /home/ec2-user.broken" || {
  error "Injection failed - /home/ec2-user.broken not found"
  exit 1
}

# ---------- print alert ----------
echo ""
echo "============================================================"
echo "  ALERT: Cannot SSH into server - getting errors"
echo "  SSH login succeeds but user profile is broken."
echo "  The .bash_profile, .bashrc and other config files are"
echo "  missing from the home directory."
echo "============================================================"
echo ""
info "State saved to ${STATE_FILE}"
info "Candidate should diagnose and restore the home directory."
