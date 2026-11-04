#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/06-alter-system-lock
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module04-06; mkdir -p "$STATE_DIR"

AUTO="$PGDATA/postgresql.auto.conf"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "shared_buffers is 256MB (from conf.d)" "256MB" "$(psq postgres 'SHOW shared_buffers' 2>/dev/null)"
check_eq "work_mem is 16MB (from conf.d)" "16MB" "$(psq postgres 'SHOW work_mem' 2>/dev/null)"
lm=$(psq postgres 'SHOW log_min_duration_statement' 2>/dev/null)
if [[ -n "$lm" && "$lm" != "0" ]]; then ok "log_min_duration_statement is not 0 ($lm)"; else bad "log_min_duration_statement is not 0 (got ${lm:-<none>})"; fi
n=$(grep -cvE '^[[:space:]]*(#|$)' "$AUTO" 2>/dev/null)
check_eq "postgresql.auto.conf has no parameter overrides" "0" "${n:-<none>}"
finish
