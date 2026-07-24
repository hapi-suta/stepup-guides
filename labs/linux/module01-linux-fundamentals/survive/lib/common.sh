#!/usr/bin/env bash
# lib/common.sh - Shared helpers for chaos scenarios.
# Sourced after config.sh by every inject/validate script.

# ---------- output helpers ----------
info()    { printf "\033[0;34m[INFO]\033[0m  %s\n" "$*"; }
success() { printf "\033[0;32m[PASS]\033[0m  %s\n" "$*"; }
warn()    { printf "\033[0;33m[WARN]\033[0m  %s\n" "$*"; }
error()   { printf "\033[0;31m[FAIL]\033[0m  %s\n" "$*"; }
header()  { printf "\n\033[1;36m=== %s ===\033[0m\n\n" "$*"; }
step()    { printf "\033[0;35m[STEP]\033[0m  %s\n" "$*"; }

# ---------- remote execution ----------
# Usage: remote_exec <host> <command>
remote_exec() {
  local host="$1"; shift
  # shellcheck disable=SC2029
  ssh $SSH_OPTS "${SSH_USER}@${host}" "$@"
}

# ---------- validation check ----------
# Usage: check <description> <command...>
# Returns 0 on success, 1 on failure. Prints PASS/FAIL.
CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    success "$desc"
    (( CHECKS_PASSED++ ))
    return 0
  else
    error "$desc"
    (( CHECKS_FAILED++ ))
    return 1
  fi
}

# Print summary after all checks run.
check_summary() {
  echo ""
  info "Results: ${CHECKS_PASSED} passed, ${CHECKS_FAILED} failed"
  if (( CHECKS_FAILED > 0 )); then
    error "SCENARIO NOT RESOLVED"
    return 1
  else
    success "ALL CHECKS PASSED"
    return 0
  fi
}
