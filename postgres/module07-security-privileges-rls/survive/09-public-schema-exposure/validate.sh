#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/09-public-schema-exposure
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
check_eq "PUBLIC does not have CREATE on schema public" "0" "$(psq stepup_store "SELECT count(*) FROM pg_namespace n, aclexplode(n.nspacl) a WHERE n.nspname = 'public' AND a.grantee = 0 AND a.privilege_type = 'CREATE'" 2>/dev/null)"
check_eq "no trap tables (connection_log, temp_staging) exist" "0" "$(psq stepup_store "SELECT count(*) FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname IN ('connection_log','temp_staging')" 2>/dev/null)"
check_eq "no shadowing version() function in public" "0" "$(psq stepup_store "SELECT count(*) FROM pg_proc WHERE proname = 'version' AND pronamespace = 'public'::regnamespace" 2>/dev/null)"
check_eq "unprivileged app_user cannot create objects in public" "f" "$(psq stepup_store "SELECT has_schema_privilege('app_user', 'public', 'CREATE')" 2>/dev/null)"
finish
