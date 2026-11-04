#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/10-grant-option-chain
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
for r in data_engineer analyst_jr intern_viewer; do
  check_eq "$r can SELECT from customer_data" "t" "$(psq stepup_store "SELECT has_table_privilege('$r', 'public.customer_data', 'SELECT')" 2>/dev/null)"
  c=$(psq stepup_store "SET ROLE $r; SELECT count(*) FROM customer_data" 2>/dev/null)
  if [[ "${c:-0}" -ge 1 ]]; then ok "$r can query customer_data ($c rows)"; else bad "$r can query customer_data (expected >=1 rows, got ${c:-<error>})"; fi
done
for p in SELECT INSERT UPDATE DELETE; do
  check_eq "sec_admin still has $p on customer_data" "t" "$(psq stepup_store "SELECT has_table_privilege('sec_admin', 'public.customer_data', '$p')" 2>/dev/null)"
done
finish
