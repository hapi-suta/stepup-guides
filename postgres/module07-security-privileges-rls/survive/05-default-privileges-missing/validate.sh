#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/05-default-privileges-missing
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
for t in inventory shipments; do
  check_eq "app_user can SELECT from $t" "t" "$(psq stepup_store "SELECT has_table_privilege('app_user', 'public.$t', 'SELECT')" 2>/dev/null)"
done
dq="SELECT count(*) FROM pg_default_acl d, aclexplode(d.defaclacl) a WHERE d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'r' AND a.grantee = 'app_user'::regrole AND a.privilege_type = 'SELECT'"
d=$(psq stepup_store "$dq" 2>/dev/null)
if [[ "${d:-0}" -ge 1 ]]; then ok "ALTER DEFAULT PRIVILEGES are configured for tables"; else bad "ALTER DEFAULT PRIVILEGES are configured for tables (no default SELECT for app_user in public)"; fi
if [[ "${d:-0}" -ge 1 ]]; then ok "new tables will automatically get grants"; else bad "new tables will automatically get grants (default ACL missing)"; fi
finish
