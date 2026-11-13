#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/10-pg-hba-blocks-connections
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
STATE_DIR=/var/lib/suta-survive/module04-10; mkdir -p "$STATE_DIR"

HBA="$PGDATA/pg_hba.conf"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "psql connects successfully to labdb" "1" "$(psq labdb 'SELECT 1' 2>/dev/null)"
if grep -qE '^[[:space:]]*(local|host|hostssl|hostnossl)[[:space:]].*[[:space:]]reject([[:space:]]|$)' "$HBA"; then bad "no reject rule in pg_hba.conf"; else ok "no reject rule in pg_hba.conf"; fi
check_eq "pg_hba_file_rules shows no reject entries" "0" "$(psq postgres "SELECT count(*) FROM pg_hba_file_rules WHERE auth_method = 'reject'" 2>/dev/null)"
check_eq "connection to postgres database also works" "1" "$(psq postgres 'SELECT 1' 2>/dev/null)"
finish
