#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/01-postgresql-conf-syntax-error
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
if grep -qF 'extra_garbage' "$CONF"; then bad "chaos injection line removed from postgresql.conf"; else ok "chaos injection line removed from postgresql.conf"; fi
if sudo -u postgres "$PGBIN/postgres" -D "$PGDATA" -C work_mem >/dev/null 2>&1; then ok "postgresql.conf has no syntax errors"; else bad "postgresql.conf has no syntax errors"; fi
wm=$(psq postgres "show work_mem" 2>/dev/null)
if [[ "$wm" =~ ^[0-9]+(kB|MB|GB)$ ]]; then ok "work_mem shows a valid value ($wm)"; else bad "work_mem shows a valid value (got ${wm:-<none>})"; fi
finish
