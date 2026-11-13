#!/usr/bin/env bash
# SUTA survive scenario: module06-users-roles-connections/09-connection-limit-reached
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
lim=$(psq postgres "SELECT rolconnlimit FROM pg_roles WHERE rolname = 'app_user'" 2>/dev/null)
if [[ -n "$lim" && "$lim" != "1" && "$lim" != "0" ]]; then ok "app_user CONNECTION LIMIT is greater than 1 ($lim)"; else bad "app_user CONNECTION LIMIT is greater than 1 (expected >1 or -1, got ${lim:-<empty>})"; fi
check_eq "no blocking pg_sleep sessions for app_user" "0" "$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE usename = 'app_user' AND query LIKE '%pg_sleep%' AND pid <> pg_backend_pid()" 2>/dev/null)"
check_eq "app_user can establish a new connection" "app_user" "$(tcp_as app_user apppass123 "SELECT current_user")"
finish
