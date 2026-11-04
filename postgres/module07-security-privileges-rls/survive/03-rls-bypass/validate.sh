#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/03-rls-bypass
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
check_eq "RLS is enabled on orders" "t" "$(psq stepup_store "SELECT relrowsecurity FROM pg_class WHERE oid = 'public.orders'::regclass" 2>/dev/null)"
check_eq "permissive gap policy rls_gap_policy is removed" "0" "$(psq stepup_store "SELECT count(*) FROM pg_policies WHERE tablename = 'orders' AND policyname = 'rls_gap_policy'" 2>/dev/null)"
check_eq "tenant_beta cannot see tenant_alpha rows" "0" "$(psq stepup_store "SET ROLE tenant_beta; SELECT count(*) FROM orders WHERE tenant_id = 'tenant_alpha'" 2>/dev/null)"
a=$(psq stepup_store "SET ROLE tenant_alpha; SELECT count(*) FROM orders WHERE tenant_id = 'tenant_alpha'" 2>/dev/null)
if [[ "${a:-0}" -ge 1 ]]; then ok "tenant_alpha can still see their own rows ($a)"; else bad "tenant_alpha can still see their own rows (expected >=1, got ${a:-<empty>})"; fi
finish
