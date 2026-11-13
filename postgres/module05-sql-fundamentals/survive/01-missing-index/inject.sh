#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/01-missing-index
# inject.sh - breaks the lab (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module05-01; mkdir -p "$STATE_DIR"

[[ -x "$PGBIN/postgres" ]] || { say "postgresql-16 is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
DB=stepup_store
psq "$DB" 'CREATE TABLE IF NOT EXISTS orders_chaos (order_id serial PRIMARY KEY, customer_id int NOT NULL, status text, amount numeric(10,2), note text, created_at timestamptz DEFAULT now())' >/dev/null
n=$(psq "$DB" 'SELECT count(*) FROM orders_chaos')
if [[ "$n" -lt 1000 ]]; then
  psq "$DB" "INSERT INTO orders_chaos (customer_id, status, amount, note) SELECT (g % 100) + 1, 'shipped', (g % 500) + 0.99, repeat('x', 20) FROM generate_series(1, 80000) g" >/dev/null
fi
psq "$DB" 'DROP INDEX IF EXISTS idx_orders_chaos_customer' >/dev/null
for ix in $(psq "$DB" "SELECT indexname FROM pg_indexes WHERE tablename = 'orders_chaos' AND indexdef ~ '\(customer_id' AND indexname <> 'orders_chaos_pkey'"); do
  psq "$DB" "DROP INDEX IF EXISTS \"$ix\"" >/dev/null
done
psq "$DB" 'ANALYZE orders_chaos' >/dev/null
say "orders_chaos rows: $(psq "$DB" 'SELECT count(*) FROM orders_chaos')"
say ""
say 'ALERT: Customer order lookup queries are running slow.'
say 'The Pulse dashboard is timing out when loading customer order history.'
say 'Queries that used to take <1ms now take hundreds of milliseconds.'
exit 0
