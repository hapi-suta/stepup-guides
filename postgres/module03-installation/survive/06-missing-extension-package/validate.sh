#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/06-missing-extension-package
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
if rpm -q postgresql16-contrib >/dev/null 2>&1; then ok "postgresql16-contrib package is installed"; else bad "postgresql16-contrib package is installed"; fi
if [[ -f /usr/pgsql-16/share/extension/pgcrypto.control ]]; then ok "pgcrypto.control is back"; else bad "pgcrypto.control is back"; fi
check_eq "pgcrypto is available to CREATE EXTENSION" "pgcrypto" "$(psq labdb "SELECT name FROM pg_available_extensions WHERE name='pgcrypto'" 2>/dev/null)"
if [[ -f /usr/pgsql-16/lib/pg_stat_statements.so ]]; then ok "pg_stat_statements.so is back"; else bad "pg_stat_statements.so is back"; fi
finish
