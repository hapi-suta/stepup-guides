#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/01-default-partition-full
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-01
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
rows=$(cat "$STATE_DIR/rows" 2>/dev/null || echo 5000)
bounded=$(psq stepup_store "select count(distinct o.tableoid) from orders_chaos o join pg_class c on c.oid=o.tableoid where pg_get_expr(c.relpartbound,c.oid) <> 'DEFAULT' and o.order_date >= '2024-01-01' and o.order_date < '2024-04-01'" 2>/dev/null)
if [[ -n "$bounded" && "$bounded" -ge 3 ]]; then ok "orders_chaos has bounded partitions holding the 2024 data ($bounded)"; else bad "orders_chaos has bounded partitions holding the 2024 data (expected 3 or more, got ${bounded:-<none>})"; fi
check_eq "default partition has zero rows" "0" "$(psq stepup_store "select count(*) from orders_chaos o join pg_class c on c.oid=o.tableoid where pg_get_expr(c.relpartbound,c.oid) = 'DEFAULT'" 2>/dev/null)"
plan=$(psq stepup_store "explain select count(*) from orders_chaos where order_date >= '2024-01-01' and order_date < '2024-02-01'" 2>/dev/null)
n=$(grep -c 'on orders_chaos_' <<<"$plan")
if [[ "$n" == "1" ]] && ! grep -q 'orders_chaos_default' <<<"$plan"; then ok "EXPLAIN scans only one bounded partition for a single month"; else bad "EXPLAIN scans only one bounded partition for a single month (partitions scanned: $n)"; fi
check_eq "total row count matches the original injection" "$rows" "$(psq stepup_store 'select count(*) from orders_chaos' 2>/dev/null)"
finish
