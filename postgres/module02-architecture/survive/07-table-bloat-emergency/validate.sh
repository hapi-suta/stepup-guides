#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/07-table-bloat-emergency
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; finish; exit 1; fi
OPT=$(psq labdb "SELECT coalesce((SELECT reloptions::text FROM pg_class WHERE relname='chaos_bloat_test' AND relkind='r'), 'missing')" 2>/dev/null)
if [[ "$OPT" == "missing" ]]; then bad "chaos_bloat_test still exists (it was dropped; the runbook keeps it)"; 
elif [[ "$OPT" == *autovacuum_enabled=false* ]]; then bad "autovacuum is re-enabled on chaos_bloat_test (reloptions $OPT)"; else ok "autovacuum is re-enabled on chaos_bloat_test"; fi
DEAD=999999
for _ in 1 2 3 4 5; do
  DEAD=$(psq labdb "SELECT coalesce((SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='chaos_bloat_test'), 999999)" 2>/dev/null)
  [[ "${DEAD:-999999}" -lt 10000 ]] && break; sleep 1
done
if [[ "${DEAD:-999999}" -lt 10000 ]]; then ok "dead tuples reduced (n_dead_tup=$DEAD)"; else bad "dead tuples reduced (expected < 10000, got ${DEAD:-<empty>})"; fi
LV=$(psq labdb "SELECT coalesce((SELECT last_vacuum IS NOT NULL OR last_autovacuum IS NOT NULL FROM pg_stat_user_tables WHERE relname='chaos_bloat_test'), false)" 2>/dev/null)
check_eq "chaos_bloat_test has been vacuumed" "t" "$LV"
finish
