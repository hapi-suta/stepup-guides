#!/usr/bin/env bash
# validate.sh - Scenario 06: Missing Command (less removed)
# Verifies the candidate reinstalled the less package.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCENARIO_DIR}/../config.sh"
source "${SURVIVE_DIR}/lib/common.sh"

STATE_FILE="/tmp/chaos-m01-06-state.env"

header "Validating: Missing Command Recovery"

# Check 1: less command exists
check "less command is available" remote_exec "$NODE1" "which less"

# Check 2: less package is installed
check "less package is installed" remote_exec "$NODE1" "rpm -q less"

# Check 3: less actually works
check "less can display a file" remote_exec "$NODE1" \
  "echo 'test' | less -F -X"

# ---------- cleanup ----------
if (( CHECKS_FAILED == 0 )); then
  rm -f "$STATE_FILE"
  info "State file cleaned up"
fi

check_summary
