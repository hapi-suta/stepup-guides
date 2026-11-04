#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/02-table-bloat
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
STATE_DIR=/var/lib/suta-survive/module05-02; mkdir -p "$STATE_DIR"

DB=stepup_store
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "bloat_demo table exists" "bloat_demo" "$(psq "$DB" "SELECT to_regclass('public.bloat_demo')" 2>/dev/null)"
dead=$(psq "$DB" "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'bloat_demo'" 2>/dev/null)
if [[ "$dead" =~ ^[0-9]+$ && "$dead" -lt 1000 ]]; then ok "n_dead_tup is below 1000 ($dead)"; else bad "n_dead_tup is below 1000 (got ${dead:-<none>})"; fi
lv=$(psq "$DB" "SELECT (last_vacuum IS NOT NULL OR last_autovacuum IS NOT NULL)::text FROM pg_stat_user_tables WHERE relname = 'bloat_demo'" 2>/dev/null)
check_eq "table has been vacuumed" "true" "$lv"
av=$(psq "$DB" "SELECT coalesce(reloptions::text, '') FROM pg_class WHERE relname = 'bloat_demo'" 2>/dev/null)
if [[ -n "$(psq "$DB" 'SELECT 1' 2>/dev/null)" && "$av" != *"autovacuum_enabled=false"* ]]; then ok "autovacuum_enabled is not set to false"; else bad "autovacuum_enabled is not set to false (reloptions: ${av:-<none>})"; fi
finish
