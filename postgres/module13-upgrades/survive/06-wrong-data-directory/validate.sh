#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/06-wrong-data-directory
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

CONF="$PGDATA/postgresql.conf"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; fi
if grep -qE "^[[:space:]]*data_directory[[:space:]]*=.*OLD_v15|chaos injection" "$CONF"; then bad "chaos injection removed from postgresql.conf"; else ok "chaos injection removed from postgresql.conf"; fi
check_eq "data_directory is /opt/pgsql/data" "/opt/pgsql/data" "$(psq postgres 'show data_directory' 2>/dev/null)"
check_eq "stepup_store is accessible and answers queries" "1" "$(psq stepup_store 'select 1' 2>/dev/null)"
finish
