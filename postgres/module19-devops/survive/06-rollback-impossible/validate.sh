#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/06-rollback-impossible
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
DB=rollback_chaos
c=$(psq "$DB" "select count(*) from information_schema.columns where table_name='customers' and column_name='loyalty_points'" 2>/dev/null)
check_eq "customers.loyalty_points column exists" "1" "${c:-0}"
v=$(psq "$DB" "select string_agg(loyalty_points::text, ',' order by id) from customers" 2>/dev/null)
check_eq "loyalty points restored in id order" "1500,890,2300,450,3100" "$v"
finish
