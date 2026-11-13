#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/02-wrong-pg-binary-in-path
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

HOME_PG=$(getent passwd postgres | cut -d: -f6); PROF="$HOME_PG/.bash_profile"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
WH=$(sudo -iu postgres which psql 2>/dev/null | tail -1)
check_eq "psql resolves to /usr/pgsql-16/bin/psql in a postgres login shell" "/usr/pgsql-16/bin/psql" "$WH"
if grep -q '/opt/pg-src/bin' "$PROF" 2>/dev/null; then bad ".bash_profile does not prioritize /opt/pg-src/bin"; else ok ".bash_profile does not prioritize /opt/pg-src/bin"; fi
PORT=$(sudo -iu postgres psql -p 5432 -d labdb -tAXc "SHOW port" 2>/dev/null | tail -1)
check_eq "psql from the postgres login shell connects to port 5432" "5432" "$PORT"
finish
