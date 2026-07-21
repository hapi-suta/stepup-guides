#!/usr/bin/env bash
# lib/common.sh - Shared helpers for module11 logical-replication SURVIVE
# scenarios. Sourced AFTER config.sh by every inject/validate script.

# ---------- output helpers ----------
info()    { printf "\033[0;34m[INFO]\033[0m  %s\n" "$*"; }
success() { printf "\033[0;32m[PASS]\033[0m  %s\n" "$*"; }
warn()    { printf "\033[0;33m[WARN]\033[0m  %s\n" "$*"; }
error()   { printf "\033[0;31m[FAIL]\033[0m  %s\n" "$*"; }
header()  { printf "\n\033[1;36m=== %s ===\033[0m\n\n" "$*"; }
step()    { printf "\033[0;35m[STEP]\033[0m  %s\n" "$*"; }
send_alert() { printf "\n\033[1;41m ALERT \033[0m %s\n\n" "$*"; }

# ---------- remote execution ----------
# Runs over SSH, or LOCALLY when the host is loopback (lets these scripts be
# tested on a single box with two clusters; in the real 2-node lab NODE1/NODE2
# are distinct hosts and this uses SSH).
remote_exec() {
  local host="$1"; shift
  if [[ "$host" == "localhost" || "$host" == "127.0.0.1" ]]; then
    bash -c "$*"
  else
    # shellcheck disable=SC2029
    ssh $SSH_OPTS "${SSH_USER}@${host}" "$@"
  fi
}

# psql on the publisher / subscriber as the postgres OS user (single command).
pub_psql() { remote_exec "$PUB_HOST" "sudo -u postgres $PGBIN/psql -p $PUB_PORT -d $DBNAME -tAc \"$1\""; }
sub_psql() { remote_exec "$SUB_HOST" "sudo -u postgres $PGBIN/psql -p $SUB_PORT -d $DBNAME -tAc \"$1\""; }

# ---------- validation helpers ----------
CHECKS_PASSED=0
CHECKS_FAILED=0
check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    success "$desc (got: $actual)"; CHECKS_PASSED=$((CHECKS_PASSED + 1)); return 0
  else
    error "$desc (expected: $expected, got: $actual)"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); return 1
  fi
}
pass() { success "$1"; CHECKS_PASSED=$((CHECKS_PASSED + 1)); }
fail() { error "$1"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }

check_summary() {
  echo ""
  info "Results: ${CHECKS_PASSED} passed, ${CHECKS_FAILED} failed"
  if (( CHECKS_FAILED > 0 )); then
    error "SCENARIO NOT RESOLVED"; return 1
  else
    success "ALL CHECKS PASSED"; return 0
  fi
}
