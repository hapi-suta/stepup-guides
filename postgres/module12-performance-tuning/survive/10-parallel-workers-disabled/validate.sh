#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/10-parallel-workers-disabled
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-10
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
g() { psq stepup_store "show $1" 2>/dev/null; }
a=$(g max_parallel_workers_per_gather); b=$(g max_parallel_workers)
if [[ -n "$a" && "$a" -ge 1 ]]; then ok "max_parallel_workers_per_gather is at least 1 ($a)"; else bad "max_parallel_workers_per_gather is at least 1 (got ${a:-<none>})"; fi
if [[ -n "$b" && "$b" -ge 1 ]]; then ok "max_parallel_workers is at least 1 ($b)"; else bad "max_parallel_workers is at least 1 (got ${b:-<none>})"; fi
plan=$(psq stepup_store "explain select txn_type, sum(amount), count(*) from chaos10_transactions group by txn_type" 2>/dev/null)
if grep -q 'Parallel Seq Scan' <<<"$plan"; then ok "EXPLAIN shows a parallel plan on the large table"; else bad "EXPLAIN shows a parallel plan on the large table (got: $(head -1 <<<"$plan"))"; fi
if grep -Eq "^max_parallel[a-z_]* *= *'?0'?$" "$PGDATA/postgresql.auto.conf" 2>/dev/null; then bad "postgresql.auto.conf does not set parallel workers to 0"; else ok "postgresql.auto.conf does not set parallel workers to 0"; fi
finish
