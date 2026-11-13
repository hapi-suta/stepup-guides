#!/usr/bin/env bash
# SUTA survive scenario: module20-capstone/03-performance-degradation-cascade
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module20-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
DB=appdb
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
pg_up || { say "PostgreSQL is not running"; exit 1; }
if [[ "$(psq "$DB" "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname in ('orders','order_items','customers')" 2>/dev/null)" != "3" ]]; then
  say "PRECONDITION: finish Tutorial 1 (production deployment: appdb with app.customers, app.orders, app.order_items) first"; exit 2
fi
# 1. seed enough rows to make a missing index and bloat visible (once)
if [[ "$(psq "$DB" "select count(*) from app.orders where order_number like 'CASC-%'")" == "0" ]]; then
  psq "$DB" "INSERT INTO app.customers (email, full_name) SELECT 'cascade-seed@capstone.lab','Cascade Seed' WHERE NOT EXISTS (SELECT 1 FROM app.customers)" >/dev/null
  psq "$DB" "INSERT INTO app.orders (customer_id, order_number, status, total_cents) SELECT (SELECT min(id) FROM app.customers), 'CASC-'||g, 'shipped', 1000 FROM generate_series(1,30000) g" >/dev/null
fi
# 2. missing indexes, autovacuum off on orders
psq "$DB" "DROP INDEX IF EXISTS app.idx_orders_customer_id; DROP INDEX IF EXISTS app.idx_orders_status; DROP INDEX IF EXISTS app.idx_order_items_order_id; ALTER TABLE app.orders SET (autovacuum_enabled = false)" >/dev/null
# 3. bad configuration (shared_buffers needs a restart)
[[ -f "$STATE_DIR/config.before" ]] || psq postgres "select name||'='||setting from pg_settings where name in ('shared_buffers','work_mem','random_page_cost','effective_cache_size')" >"$STATE_DIR/config.before"
for kv in "shared_buffers = '32MB'" "work_mem = '64kB'" "random_page_cost = 8" "effective_cache_size = '256MB'"; do psq postgres "ALTER SYSTEM SET $kv" >/dev/null; done
systemctl restart postgresql-16 >/dev/null 2>&1; wait_up
# 4. connection leak: idle-in-transaction sessions that hold a snapshot, then bloat the table behind them
n=$(psq postgres "select count(*) from pg_stat_activity where state='idle in transaction'")
for _ in $(seq $(( n + 1 )) 20); do
  setsid nohup bash -c "(echo 'BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM app.customers;'; sleep 1800) | sudo -u postgres $PGBIN/psql -p $PGPORT -d $DB -q >/dev/null 2>&1" </dev/null >/dev/null 2>&1 &
done
sleep 3
psq "$DB" "UPDATE app.orders SET total_cents = total_cents + 1; UPDATE app.orders SET total_cents = total_cents + 1" >/dev/null
sleep 2
say "idle in transaction: $(psq postgres "select count(*) from pg_stat_activity where state='idle in transaction'")"
say "shared_buffers: $(psq postgres 'show shared_buffers')  work_mem: $(psq postgres 'show work_mem')"
say ""
say "ALERT: High - Application slow, multiple root causes."
say "Queries that were fast yesterday now take many seconds, and the load keeps climbing."
exit 0
