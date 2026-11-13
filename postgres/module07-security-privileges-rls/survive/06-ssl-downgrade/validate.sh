#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/06-ssl-downgrade
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
check_eq "SSL is enabled (SHOW ssl returns on)" "on" "$(psq postgres 'SHOW ssl' 2>/dev/null)"
n=$(psq postgres "SELECT count(*) FROM pg_hba_file_rules WHERE type = 'hostssl'" 2>/dev/null)
if [[ "${n:-0}" -ge 1 ]]; then ok "pg_hba.conf contains hostssl entries ($n)"; else bad "pg_hba.conf contains hostssl entries (expected >=1, got ${n:-0})"; fi
check_eq "no non-loopback host (unencrypted-allowed) rules remain" "0" "$(psq postgres "SELECT count(*) FROM pg_hba_file_rules WHERE type = 'host' AND address IS NOT NULL AND address NOT IN ('127.0.0.1','::1')" 2>/dev/null)"
check_eq "SSL connections work" "t" "$(PGSSLMODE=require tcp_as app_user apppass123 "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")"
finish
