#!/usr/bin/env bash
# SUTA survive scenario: module06-users-roles-connections/03-max-connections-exhausted
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
tcp_as() { PGCONNECT_TIMEOUT=5 PGPASSWORD="$2" "$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U "$1" -d "${4:-stepup_store}" -v ON_ERROR_STOP=1 -tAXqc "$3" 2>/dev/null; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running (not accepting connections)"; fi
mc=$(psq postgres "SHOW max_connections" 2>/dev/null)
if [[ "${mc:-0}" -ge 50 ]]; then ok "max_connections is at least 50 ($mc)"; else bad "max_connections is at least 50 (expected >=50, got ${mc:-<empty>})"; fi
check_eq "no pending_restart on max_connections" "f" "$(psq postgres "SELECT pending_restart FROM pg_settings WHERE name = 'max_connections'" 2>/dev/null)"
check_eq "app_user can connect via TCP" "app_user" "$(tcp_as app_user apppass123 "SELECT current_user")"
finish
