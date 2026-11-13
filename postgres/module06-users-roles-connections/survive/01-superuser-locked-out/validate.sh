#!/usr/bin/env bash
# SUTA survive scenario: module06-users-roles-connections/01-superuser-locked-out
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
HBA="$PGDATA/pg_hba.conf"
if [[ "$(psq postgres "SELECT 1" 2>/dev/null)" == "1" ]]; then ok "postgres can connect via Unix socket"; else bad "postgres can connect via Unix socket"; fi
check_eq "postgres can connect via TCP with the known password" "stepup_store" "$(tcp_as postgres pgadminpass123 "SELECT current_database()")"
if grep -Eq '^local[[:space:]]+all[[:space:]]+(all|postgres)[[:space:]]+(trust|peer)' "$HBA"; then ok "pg_hba.conf has a local trust/peer rule"; else bad "pg_hba.conf has a local trust/peer rule (none found)"; fi
check_eq "stepup_store database is accessible" "1" "$(psq stepup_store "SELECT 1" 2>/dev/null)"
finish
