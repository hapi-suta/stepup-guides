#!/usr/bin/env bash
# validate.sh - Scenario 03: Wrong File Permissions
# Verifies the candidate restored correct permissions on /etc/hosts.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-03-state.env"

header "Validating: Wrong File Permissions Recovery"

# Check 1: /etc/hosts is readable
check "/etc/hosts is readable" remote_exec "$NODE1" "cat /etc/hosts"

# Check 2: Permission is 644
check "/etc/hosts has permission 644" bash -c "
  perms=\$(ssh $SSH_OPTS ${SSH_USER}@${NODE1} \"stat -c '%a' /etc/hosts\")
  [[ \"\$perms\" == '644' ]]
"

# Check 3: Owner is root:root
check "/etc/hosts owned by root:root" bash -c "
  owner=\$(ssh $SSH_OPTS ${SSH_USER}@${NODE1} \"stat -c '%U:%G' /etc/hosts\")
  [[ \"\$owner\" == 'root:root' ]]
"

# Check 4: File contains localhost entry
check "/etc/hosts contains localhost entry" remote_exec "$NODE1" \
  "grep -q 'localhost' /etc/hosts"

# ---------- cleanup ----------
if (( CHECKS_FAILED == 0 )); then
  rm -f "$STATE_FILE"
  info "State file cleaned up"
fi

check_summary
