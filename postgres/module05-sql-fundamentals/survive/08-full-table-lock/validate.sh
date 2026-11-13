#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/08-full-table-lock
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
STATE_DIR=/var/lib/suta-survive/module05-08; mkdir -p "$STATE_DIR"

DB=stepup_store
lt() { sudo -u postgres env PGOPTIONS='-c lock_timeout=3000' "$PGBIN/psql" -p "$PGPORT" -d "$DB" -v ON_ERROR_STOP=1 -tAXqc "$1"; }
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "products table exists" "products" "$(psq "$DB" "SELECT to_regclass('public.products')" 2>/dev/null)"
check_eq "no ACCESS EXCLUSIVE lock on products" "0" "$(psq "$DB" "SELECT count(*) FROM pg_locks WHERE relation = 'public.products'::regclass AND mode = 'AccessExclusiveLock'" 2>/dev/null)"
check_eq "no sessions blocked on products" "0" "$(psq "$DB" "SELECT count(*) FROM pg_locks WHERE relation = 'public.products'::regclass AND NOT granted" 2>/dev/null)"
n=$(lt 'SELECT count(*) FROM products' 2>/dev/null)
if [[ "$n" =~ ^[0-9]+$ && "$n" -ge 1 ]]; then ok "products table is readable ($n rows)"; else bad "products table is readable (got ${n:-<lock timeout or error>})"; fi
finish
