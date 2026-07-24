#!/usr/bin/env bash
# validate.sh - Scenario 07: Disk Space Low
# Verifies the candidate freed disk space in /var.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-07-state.env"

header "Validating: Disk Space Low Recovery"

# Check 1: /var usage is below 80%
check "/var usage is below 80%" bash -c "
  usage=\$(ssh $SSH_OPTS ${SSH_USER}@${NODE1} \"df /var --output=pcent | tail -1 | tr -d ' %'\")
  (( usage < 80 ))
"

# Check 2: Large chaos dump file removed
check "chaos-old-backup-full.dump removed" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -f /var/chaos-old-backup-full.dump'
"

# Check 3: Old audit logs removed
check "chaos-old-audit.log.1 removed" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -f /var/log/chaos-old-audit.log.1'
"

check "chaos-old-audit.log.2 removed" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -f /var/log/chaos-old-audit.log.2'
"

# Check 4: Can still write to /var
check "Can write to /var" remote_exec "$NODE1" \
  "sudo touch /var/validate-test-$$ && sudo rm -f /var/validate-test-$$"

# ---------- cleanup ----------
if (( CHECKS_FAILED == 0 )); then
  rm -f "$STATE_FILE"
  info "State file cleaned up"
fi

check_summary
