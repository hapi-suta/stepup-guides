#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/09-conflicting-confd-override
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
STATE_DIR=/var/lib/suta-survive/module04-09; mkdir -p "$STATE_DIR"

check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "pg_isready succeeds on port 5432"; else bad "pg_isready succeeds on port 5432"; fi
if [[ -e "$PGDATA/conf.d/zzz-override.conf" ]]; then bad "zzz-override.conf removed from conf.d"; else ok "zzz-override.conf removed from conf.d"; fi
check_eq "psql connection on port 5432 succeeds, SHOW port" "5432" "$(psq labdb 'SHOW port' 2>/dev/null)"
sf=$(psq postgres "SELECT coalesce(sourcefile,'') FROM pg_settings WHERE name = 'port'" 2>/dev/null)
if [[ -n "$(psq postgres 'SELECT 1' 2>/dev/null)" && "$sf" != *zzz-override* ]]; then ok "port setting does not come from the conf.d override"; else bad "port setting does not come from the conf.d override (sourcefile: ${sf:-<none>})"; fi
finish
