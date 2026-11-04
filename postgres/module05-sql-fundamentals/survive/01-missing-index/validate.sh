#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/01-missing-index
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module05-01; mkdir -p "$STATE_DIR"

DB=stepup_store
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "orders_chaos table exists" "orders_chaos" "$(psq "$DB" "SELECT to_regclass('public.orders_chaos')" 2>/dev/null)"
ix=$(psq "$DB" "SELECT count(*) FROM pg_indexes WHERE tablename = 'orders_chaos' AND indexdef ~ '\(customer_id'" 2>/dev/null)
if [[ "${ix:-0}" -ge 1 ]]; then ok "an index on orders_chaos(customer_id) exists"; else bad "an index on orders_chaos(customer_id) exists (got ${ix:-0})"; fi
plan=$(psq "$DB" "EXPLAIN SELECT * FROM orders_chaos WHERE customer_id = 5" 2>/dev/null)
if [[ -n "$plan" && "$plan" != *"Seq Scan"* ]]; then ok "customer lookup plan does not use Seq Scan"; else bad "customer lookup plan does not use Seq Scan (plan: ${plan:-<none>})"; fi
finish
