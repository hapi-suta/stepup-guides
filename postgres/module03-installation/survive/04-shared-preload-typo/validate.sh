#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/04-shared-preload-typo
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

CONF="$PGDATA/postgresql.conf"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
if grep -q 'pg_stat_statments' "$CONF"; then bad "postgresql.conf has no typo"; else ok "postgresql.conf has no typo"; fi
SPL=$(psq postgres "SHOW shared_preload_libraries" 2>/dev/null)
if [[ "$SPL" == *pg_stat_statements* ]]; then ok "shared_preload_libraries has correct spelling ($SPL)"; else bad "shared_preload_libraries has correct spelling (got ${SPL:-<empty>})"; fi
if psq labdb "SELECT count(*) FROM pg_stat_statements" >/dev/null 2>&1; then ok "pg_stat_statements extension works"; else bad "pg_stat_statements extension works"; fi
finish
