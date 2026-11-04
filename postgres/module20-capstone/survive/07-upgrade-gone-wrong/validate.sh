#!/usr/bin/env bash
# SUTA survive scenario: module20-capstone/07-upgrade-gone-wrong
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
DB=appdb; ST=/tmp/stepup-capstone-07-state.env
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if [[ -e "$PGDATA/pg_wal.broken" ]]; then bad "pg_wal.broken no longer present"; else ok "pg_wal.broken no longer present"; fi
if [[ -e "$PGDATA/pg_wal" ]]; then ok "pg_wal is in place"; else bad "pg_wal is in place"; fi
if [[ -e /opt/pgsql/data_new ]]; then bad "failed upgrade directory /opt/pgsql/data_new removed"; else ok "failed upgrade directory /opt/pgsql/data_new removed"; fi
if [[ -f "$ST" ]]; then
  # shellcheck disable=SC1090
  . "$ST"
  check_eq "app.orders row count matches pre-upgrade state" "${ORDERS_COUNT:-?}" "$(psq appdb 'select count(*) from app.orders' 2>/dev/null)"
  check_eq "app.customers row count matches pre-upgrade state" "${CUSTOMERS_COUNT:-?}" "$(psq appdb 'select count(*) from app.customers' 2>/dev/null)"
else
  bad "state file $ST present (needed to compare row counts)"
fi
check_eq "server major version" "16" "$(psq postgres "show server_version_num" 2>/dev/null | cut -c1-2)"
finish
