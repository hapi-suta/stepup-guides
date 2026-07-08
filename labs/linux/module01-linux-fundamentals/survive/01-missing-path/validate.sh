#!/usr/bin/env bash
# validate.sh - Scenario 01: Missing PATH (grep hidden)
# Verifies the candidate restored grep to its correct location.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-01-state.env"

header "Validating: Missing PATH Recovery"

# Check 1: grep command exists
check "grep command is available" remote_exec "$NODE1" "which grep"

# Check 2: grep is in the correct location
check "grep is at /usr/bin/grep" remote_exec "$NODE1" "test -f /usr/bin/grep"

# Check 3: grep actually works
check "grep can search text" remote_exec "$NODE1" "echo 'hello world' | grep 'hello'"

# Check 4: grep.hidden does not exist (was moved back properly)
check "grep.hidden no longer exists" bash -c "
  ! ssh $SSH_OPTS ${SSH_USER}@${NODE1} 'test -f /usr/bin/grep.hidden'
"

# ---------- cleanup ----------
if (( CHECKS_FAILED == 0 )); then
  rm -f "$STATE_FILE"
  info "State file cleaned up"
fi

check_summary
