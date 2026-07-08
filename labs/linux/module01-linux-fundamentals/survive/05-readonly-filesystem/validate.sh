#!/usr/bin/env bash
# validate.sh - Scenario 05: Read-Only Filesystem
# Verifies the candidate restored write access to /opt.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-05-state.env"

header "Validating: Read-Only Filesystem Recovery"

# Check 1: /opt is writable
check "/opt is writable" remote_exec "$NODE1" \
  "sudo touch /opt/validate-test-$$ && sudo rm -f /opt/validate-test-$$"

# Check 2: /opt does not have ro mount option
check "/opt is not mounted read-only" bash -c "
  mount_info=\$(ssh $SSH_OPTS ${SSH_USER}@${NODE1} \"mount | grep ' /opt '\" 2>/dev/null || echo '')
  if [[ -n \"\$mount_info\" ]]; then
    echo \"\$mount_info\" | grep -qv ',ro,'
  else
    # /opt is part of root filesystem, no separate mount - that is fine
    true
  fi
"

# Check 3: Can create a directory in /opt
check "Can create directory in /opt" remote_exec "$NODE1" \
  "sudo mkdir -p /opt/validate-dir-$$ && sudo rmdir /opt/validate-dir-$$"

# ---------- cleanup ----------
if (( CHECKS_FAILED == 0 )); then
  rm -f "$STATE_FILE"
  info "State file cleaned up"
fi

check_summary
