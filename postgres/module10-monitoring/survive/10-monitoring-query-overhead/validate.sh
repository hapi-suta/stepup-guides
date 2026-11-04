#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/10-monitoring-query-overhead
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-10
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2" 2>/dev/null; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
# check_lt desc limit actual : PASS when actual is an integer below limit
check_lt() { local d="$1" l="$2" a="$3"; [[ "$a" =~ ^[0-9]+$ && "$a" -lt "$l" ]] && ok "$d" || bad "$d (expected < $l, got ${a:-<empty>})"; }
# check_ge desc limit actual : PASS when actual is an integer >= limit
check_ge() { local d="$1" l="$2" a="$3"; [[ "$a" =~ ^-?[0-9]+$ && "$a" -ge "$l" ]] && ok "$d" || bad "$d (expected >= $l, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
pg_up && ok "PostgreSQL is running" || bad "PostgreSQL is running"
ls_=$(psq postgres "SHOW log_statement")
if [[ -n "$ls_" && "$ls_" != "all" ]]; then ok "log_statement is not 'all' ($ls_)"; else bad "log_statement is not 'all' (got ${ls_:-<empty>})"; fi
check_ge "log_min_duration_statement is 1000ms or higher" 1000 "$(psq postgres "SELECT setting FROM pg_settings WHERE name='log_min_duration_statement'")"
check_eq "log_parser_stats is off" "off" "$(psq postgres "SHOW log_parser_stats")"
check_eq "log_planner_stats is off" "off" "$(psq postgres "SHOW log_planner_stats")"
check_eq "log_executor_stats is off" "off" "$(psq postgres "SHOW log_executor_stats")"
pg_up && ok "PostgreSQL accepts connections" || bad "PostgreSQL accepts connections"
finish
