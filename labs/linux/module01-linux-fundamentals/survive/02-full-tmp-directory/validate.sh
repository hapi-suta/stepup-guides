#!/usr/bin/env bash
# validate.sh - Scenario 02: Full /tmp Directory
# Verifies the candidate freed up space in /tmp.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-02-state.env"

header "Validating: Full /tmp Directory Recovery"

# Check 1: /tmp usage is below 80%
check "/tmp usage is below 80%" bash -c "
  usage=\$(ssh $SSH_OPTS ${SSH_USER}@${NODE1} \"df /tmp --output=pcent | tail -1 | tr -d ' %'\")
  (( usage < 80 ))
"

# Check 2: chaos big files are removed
check "chaos-bigfile-01.dat removed" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -f /tmp/chaos-bigfile-01.dat'
"

check "chaos-bigfile-02.dat removed" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -f /tmp/chaos-bigfile-02.dat'
"

check "chaos-bigfile-03.dat removed" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -f /tmp/chaos-bigfile-03.dat'
"

check "chaos-old-sort-result.tmp removed" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -f /tmp/chaos-old-sort-result.tmp'
"

# Check 3: Can create a temp file (functional test)
check "Can create a new temp file in /tmp" remote_exec "$NODE1" \
  "touch /tmp/validate-test-$$ && rm -f /tmp/validate-test-$$"

# ---------- cleanup ----------
if (( CHECKS_FAILED == 0 )); then
  rm -f "$STATE_FILE"
  info "State file cleaned up"
fi

check_summary
