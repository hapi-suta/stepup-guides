#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/06-partition-pruning-disabled
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-06
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
check_eq "enable_partition_pruning is on" "on" "$(psq stepup_store 'show enable_partition_pruning' 2>/dev/null)"
plan=$(psq stepup_store "explain select * from chaos6_sales where sale_date = '2024-03-15'" 2>/dev/null)
n=$(grep -c 'chaos6_sales_2024_' <<<"$plan")
if [[ "$n" == "1" ]] && grep -q 'chaos6_sales_2024_03' <<<"$plan"; then ok "EXPLAIN scans only the March partition"; else bad "EXPLAIN scans only the March partition (partitions scanned: $n)"; fi
if grep -Eq '^enable_partition_pruning *=' "$PGDATA/postgresql.auto.conf" 2>/dev/null; then bad "postgresql.auto.conf has no partition pruning override"; else ok "postgresql.auto.conf has no partition pruning override"; fi
finish
