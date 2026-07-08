#!/usr/bin/env bash
# DESC: Deletes the target of a symlink to simulate a missing config
# =============================================================================
# SCENARIO 08 - Broken Symlink
# Creates a symlink to a config file, then deletes the target. The candidate
# must understand symlinks, diagnose the broken link, and recreate the target.
# =============================================================================

set -euo pipefail
SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-08-state.env"

header "Injecting Chaos: Broken Symlink"

# ---------- confirm connectivity ----------
step "Verifying SSH connectivity to NODE1"
if ! remote_exec "$NODE1" "echo ok" >/dev/null 2>&1; then
  error "Cannot SSH into NODE1 - aborting injection"
  exit 1
fi
info "SSH connectivity confirmed"

# ---------- create the scenario ----------
step "Setting up symlink scenario"
remote_exec "$NODE1" "
  # Create a config directory structure
  sudo mkdir -p /opt/app/config
  sudo mkdir -p /opt/app/shared

  # Create the original config file
  cat <<'CFGEOF' | sudo tee /opt/app/shared/app.conf > /dev/null
# Application Configuration
listen_address = 0.0.0.0
listen_port = 5432
max_connections = 100
log_level = info
data_directory = /opt/app/data
CFGEOF

  # Create a symlink that points to the config
  sudo ln -sf /opt/app/shared/app.conf /opt/app/config/app.conf
"

# ---------- save state ----------
step "Saving original state"
cat > "$STATE_FILE" <<STEOF
INJECT_TIMESTAMP=$(date +%s)
SYMLINK_PATH=/opt/app/config/app.conf
TARGET_PATH=/opt/app/shared/app.conf
STEOF

# ---------- verify symlink works before breaking it ----------
step "Verifying symlink works"
remote_exec "$NODE1" "cat /opt/app/config/app.conf" >/dev/null

# ---------- delete the target file ----------
step "Deleting symlink target"
remote_exec "$NODE1" "sudo rm /opt/app/shared/app.conf"

# ---------- verify injection ----------
step "Verifying symlink is now broken"
if remote_exec "$NODE1" "cat /opt/app/config/app.conf" >/dev/null 2>&1; then
  error "Symlink still works - injection failed"
  exit 1
fi
info "Symlink is now broken"

# ---------- print alert ----------
echo ""
echo "============================================================"
echo "  ALERT: Configuration file missing"
echo "  The application configuration at /opt/app/config/app.conf"
echo "  cannot be read. The application will not start without it."
echo "============================================================"
echo ""
info "State saved to ${STATE_FILE}"
info "Candidate should diagnose the broken symlink and fix it."
