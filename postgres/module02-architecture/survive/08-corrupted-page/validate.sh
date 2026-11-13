#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/08-corrupted-page
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

if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; finish; exit 1; fi
EX=$(psq labdb "SELECT to_regclass('public.chaos_corrupt_test') IS NOT NULL" 2>/dev/null)
if [[ "$EX" == "f" ]]; then ok "corrupted table chaos_corrupt_test is gone"
elif psq labdb "SELECT count(*) FROM chaos_corrupt_test" >/dev/null 2>&1; then ok "chaos_corrupt_test is readable again"
else bad "chaos_corrupt_test is gone or readable (still raising an error)"; fi
check_eq "database answers a simple query" "1" "$(psq labdb "SELECT 1" 2>/dev/null)"
check_eq "zero_damaged_pages is not left on globally" "off" "$(psq postgres "SHOW zero_damaged_pages" 2>/dev/null)"
finish
