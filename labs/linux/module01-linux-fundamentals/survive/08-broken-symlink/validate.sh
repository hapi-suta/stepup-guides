#!/usr/bin/env bash
# validate.sh - Scenario 08: Broken Symlink
# Verifies the candidate fixed the broken symlink.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-08-state.env"

header "Validating: Broken Symlink Recovery"

# Check 1: The symlink exists at /opt/app/config/app.conf
check "Symlink exists at /opt/app/config/app.conf" remote_exec "$NODE1" \
  "test -L /opt/app/config/app.conf"

# Check 2: The target file exists at /opt/app/shared/app.conf
check "Target file exists at /opt/app/shared/app.conf" remote_exec "$NODE1" \
  "test -f /opt/app/shared/app.conf"

# Check 3: The symlink is readable (not broken)
check "Symlink is readable (not broken)" remote_exec "$NODE1" \
  "cat /opt/app/config/app.conf"

# Check 4: The config file contains expected content
check "Config contains listen_port" remote_exec "$NODE1" \
  "grep -q 'listen_port' /opt/app/config/app.conf"

check "Config contains max_connections" remote_exec "$NODE1" \
  "grep -q 'max_connections' /opt/app/config/app.conf"

check "Config contains data_directory" remote_exec "$NODE1" \
  "grep -q 'data_directory' /opt/app/config/app.conf"

# ---------- cleanup ----------
if (( CHECKS_FAILED == 0 )); then
  remote_exec "$NODE1" "sudo rm -rf /opt/app" 2>/dev/null || true
  rm -f "$STATE_FILE"
  info "Test artifacts and state file cleaned up"
fi

check_summary
