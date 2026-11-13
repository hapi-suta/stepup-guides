#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/05-pg-stat-statements-missing
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
l=$(psq postgres "show shared_preload_libraries" 2>/dev/null)
if [[ "$l" == *pg_stat_statements* ]]; then ok "pg_stat_statements is in shared_preload_libraries ($l)"; else bad "pg_stat_statements is in shared_preload_libraries (got ${l:-<empty>})"; fi
c=$(psq stepup_store "select count(*) >= 0 from pg_stat_statements" 2>/dev/null)
check_eq "SELECT from pg_stat_statements works in stepup_store" "t" "$c"
finish
