#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/05-pgdata-permissions
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

check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
check_eq "$PGDATA has permissions 0700" "700" "$(stat -c %a "$PGDATA" 2>/dev/null)"
for f in postgresql.conf pg_hba.conf PG_VERSION; do
  check_eq "$f is owned by postgres:postgres" "postgres:postgres" "$(stat -c %U:%G "$PGDATA/$f" 2>/dev/null)"
done
if [[ "$(psq labdb "SELECT 'PostgreSQL is back'" 2>/dev/null)" == "PostgreSQL is back" ]]; then ok "psql connection succeeds"; else bad "psql connection succeeds"; fi
finish
