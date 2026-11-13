#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/08-orphaned-permissions
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
oq="SELECT count(*) FROM pg_class c LEFT JOIN pg_roles r ON r.oid = c.relowner WHERE r.oid IS NULL AND c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','S','v')"
check_eq "no orphaned objects with invalid owners" "0" "$(psq stepup_store "$oq" 2>/dev/null)"
for t in analytics_events analytics_metrics; do
  o=$(psq stepup_store "SELECT r.rolname FROM pg_class c JOIN pg_roles r ON r.oid = c.relowner WHERE c.oid = to_regclass('public.$t')" 2>/dev/null)
  if [[ -n "$o" ]]; then ok "$t has a valid owner ($o)"; else bad "$t has a valid owner (owner not found)"; fi
  c=$(psq stepup_store "SET ROLE app_user; SELECT count(*) FROM $t" 2>/dev/null)
  if [[ -n "$c" ]]; then ok "app_user can query $t"; else bad "app_user can query $t (permission denied or table missing)"; fi
done
finish
