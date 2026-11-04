#!/usr/bin/env bash
# SUTA survive scenario: module06-users-roles-connections/07-schema-search-path
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
sp=$(psq postgres "SELECT coalesce((SELECT array_to_string(setconfig, ',') FROM pg_db_role_setting rs JOIN pg_roles r ON r.oid = rs.setrole JOIN pg_database d ON d.oid = rs.setdatabase WHERE r.rolname = 'app_user' AND d.datname = 'stepup_store'), '')" 2>/dev/null)
if [[ -z "$sp" || "$sp" == *public* ]]; then ok "app_user search_path includes public (or is not overridden)"; else bad "app_user search_path includes public (expected public, got $sp)"; fi
check_eq "a fresh app_user session resolves orders to public.orders" "t" "$(tcp_as app_user apppass123 "SELECT to_regclass('orders') = 'public.orders'::regclass")"
check_eq "app_user queries do not return decoy data" "0" "$(tcp_as app_user apppass123 "SELECT count(*) FROM orders WHERE tenant_id = 'DECOY'")"
finish
