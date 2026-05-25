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

# ---------- postgres execution ----------
# Usage: pg_exec <host> <sql>
pg_exec() {
  local host="$1" sql="$2"
  remote_exec "$host" \
    "sudo -u postgres psql -p ${PG_PORT} -d ${PG_DB} -t -A -c \"${sql}\""
}

# ---------- repmgr execution ----------
# Usage: repmgr_exec <host> <repmgr_args>
repmgr_exec() {
  local host="$1"; shift
  remote_exec "$host" \
    "sudo -u postgres ${PG_BIN}/repmgr -f ${REPMGR_CONF} $*"
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

# ---------- topology discovery ----------
# get_primary - Returns the IP of whichever node is currently primary.
get_primary() {
  for node in "$NODE1" "$NODE2" "$NODE3"; do
    local result
    result=$(remote_exec "$node" \
      "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null) || continue
    if [[ "$result" == "f" ]]; then
      echo "$node"
      return 0
    fi
  done
  echo ""
  return 1
}

# get_standbys - Returns IPs of all nodes in recovery, one per line.
get_standbys() {
  for node in "$NODE1" "$NODE2" "$NODE3"; do
    local result
    result=$(remote_exec "$node" \
      "sudo -u postgres psql -p ${PG_PORT} -t -A -c 'SELECT pg_is_in_recovery()'" 2>/dev/null) || continue
    if [[ "$result" == "t" ]]; then
      echo "$node"
    fi
  done
}

# get_first_standby - Returns the IP of the first reachable standby.
get_first_standby() {
  get_standbys | head -1
}

# node_is_reachable - Check if a node's PostgreSQL is reachable.
node_is_reachable() {
  local host="$1"
  remote_exec "$host" "sudo -u postgres ${PG_BIN}/pg_isready -p ${PG_PORT}" >/dev/null 2>&1
}

# get_repmgr_primary - Get the primary according to repmgr cluster show.
get_repmgr_primary() {
  for node in "$NODE1" "$NODE2" "$NODE3" "$NODE4"; do
    local csv
    csv=$(repmgr_exec "$node" "cluster show --csv" 2>/dev/null) || continue
    local primary_name
    primary_name=$(echo "$csv" | grep ',primary,' | head -1 | cut -d',' -f2)
    if [[ -n "$primary_name" ]]; then
      # Resolve hostname to IP
      for n in "$NODE1" "$NODE2" "$NODE3"; do
        local hostname
        hostname=$(remote_exec "$n" "hostname" 2>/dev/null) || continue
        if [[ "$hostname" == "$primary_name" ]]; then
          echo "$n"
          return 0
        fi
      done
    fi
  done
  echo ""
  return 1
}
