#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/07-password-in-logs
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
ls_=$(psq postgres "SHOW log_statement" 2>/dev/null)
if [[ -n "$ls_" && "$ls_" != "all" ]]; then ok "log_statement is not set to 'all' ($ls_)"; else bad "log_statement is not set to 'all' (got ${ls_:-<empty>})"; fi
hits=$(grep -sl 'SuperSecret_Prod_2026\|BatchW0rk3r_Secret' "$PGLOG"/postgresql-*.log | wc -l | tr -d ' ')
check_eq "no old plaintext passwords in the log files" "0" "$hits"
if tcp_as api_service 'SuperSecret_Prod_2026!' "SELECT 1" postgres >/dev/null; then bad "api_service password was rotated (old password still works)"; else ok "api_service password was rotated"; fi
if tcp_as batch_worker 'BatchW0rk3r_Secret!' "SELECT 1" postgres >/dev/null; then bad "batch_worker password was rotated (old password still works)"; else ok "batch_worker password was rotated"; fi
finish
