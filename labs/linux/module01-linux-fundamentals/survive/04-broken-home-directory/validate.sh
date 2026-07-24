#!/usr/bin/env bash
# validate.sh - Scenario 04: Broken Home Directory
# Verifies the candidate restored the ec2-user home directory.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-04-state.env"

header "Validating: Broken Home Directory Recovery"

# Check 1: Home directory exists
check "/home/ec2-user exists" remote_exec "$NODE1" "test -d /home/ec2-user"

# Check 2: .bashrc exists
check ".bashrc exists" remote_exec "$NODE1" "test -f /home/ec2-user/.bashrc"

# Check 3: .bash_profile exists
check ".bash_profile exists" remote_exec "$NODE1" "test -f /home/ec2-user/.bash_profile"

# Check 4: .ssh directory exists with correct permissions
check ".ssh directory has permission 700" bash -c "
  perms=\$(ssh $SSH_OPTS ${SSH_USER}@${NODE1} \"stat -c '%a' /home/ec2-user/.ssh\")
  [[ \"\$perms\" == '700' ]]
"

# Check 5: authorized_keys exists
check "authorized_keys exists" remote_exec "$NODE1" \
  "test -f /home/ec2-user/.ssh/authorized_keys"

# Check 6: Home directory owned by ec2-user
check "Home directory owned by ec2-user" bash -c "
  owner=\$(ssh $SSH_OPTS ${SSH_USER}@${NODE1} \"stat -c '%U' /home/ec2-user\")
  [[ \"\$owner\" == 'ec2-user' ]]
"

# Check 7: .broken directory no longer exists
check "ec2-user.broken no longer exists" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -d /home/ec2-user.broken'
"

# ---------- cleanup ----------
if (( CHECKS_FAILED == 0 )); then
  remote_exec "$NODE1" "rm -f /tmp/authorized_keys.bak" 2>/dev/null || true
  rm -f "$STATE_FILE"
  info "State file cleaned up"
fi

check_summary
