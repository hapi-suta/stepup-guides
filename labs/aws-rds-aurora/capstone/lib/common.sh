#!/usr/bin/env bash
# capstone/lib/common.sh
# Helper functions for capstone validation.
# Reuses the same pattern as survive/lib/common.sh across all tiers.

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }

# ---------------------------------------------------------------------------
# Check result and track pass/fail counts
# ---------------------------------------------------------------------------

_CHECK_PASS=0
_CHECK_FAIL=0

check() {
  local label="$1"
  local result="$2"   # "pass" or "fail"
  local detail="${3:-}"

  if [[ "$result" == "pass" ]]; then
    success "$label"
    (( _CHECK_PASS++ )) || true
  else
    fail "$label"
    if [[ -n "$detail" ]]; then
      echo "        Detail: $detail"
    fi
    (( _CHECK_FAIL++ )) || true
  fi
}

check_summary() {
  echo ""
  echo "================================"
  echo "  Results: ${_CHECK_PASS} passed, ${_CHECK_FAIL} failed"
  echo "================================"
  if [[ $_CHECK_FAIL -gt 0 ]]; then
    echo ""
    warn "Some checks failed. See details above."
    return 1
  else
    success "All checks passed."
    return 0
  fi
}
