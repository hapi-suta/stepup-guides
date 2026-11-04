#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/09-stale-statistics
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
OPT=$(psq labdb "SELECT coalesce((SELECT reloptions::text FROM pg_class WHERE relname='chaos_stats_test' AND relkind='r'), 'missing')" 2>/dev/null)
if [[ "$OPT" == "missing" ]]; then bad "chaos_stats_test exists"
elif [[ "$OPT" == *autovacuum_enabled=false* ]]; then bad "autovacuum is re-enabled on chaos_stats_test (reloptions $OPT)"; else ok "autovacuum is re-enabled on chaos_stats_test"; fi
RT=$(psq labdb "SELECT coalesce((SELECT reltuples::bigint FROM pg_class WHERE relname='chaos_stats_test'), -1)" 2>/dev/null)
if [[ -n "$RT" && "$RT" -ge 0 && "$RT" -lt 50000 ]]; then ok "planner row estimate refreshed (reltuples=$RT)"; else bad "planner row estimate refreshed (expected < 50000, got ${RT:-<empty>})"; fi
EST=$(sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d labdb -tAXqc "EXPLAIN SELECT * FROM chaos_stats_test WHERE category = 42" 2>/dev/null | head -1 | sed -n 's/.*rows=\([0-9]*\).*/\1/p')
if [[ -n "$EST" && "$EST" -le 50 ]]; then ok "EXPLAIN estimates $EST rows for category = 42"; else bad "EXPLAIN estimates few rows for category = 42 (expected <= 50, got ${EST:-<empty>})"; fi
finish
