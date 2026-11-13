#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/11-stale-stats-after-bulk-delete
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-11; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
psqf() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXq; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and would not start"; exit 1; }; }
reload() { psq postgres "select pg_reload_conf()" >/dev/null; sleep 1; }
# seed: stepup_store and its base tables (idempotent, same shape as the build guides)
if [[ "$(psq postgres "select count(*) from pg_database where datname='stepup_store'")" != "1" ]]; then
  sudo -u postgres "$PGBIN/createdb" -p "$PGPORT" stepup_store && say "created database stepup_store"
fi
psqf stepup_store <<'SQL'
CREATE TABLE IF NOT EXISTS products (product_id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL, category VARCHAR(50), price NUMERIC(10,2) NOT NULL, stock INTEGER DEFAULT 0, created_at TIMESTAMP DEFAULT now());
CREATE TABLE IF NOT EXISTS customers (customer_id SERIAL PRIMARY KEY, first_name VARCHAR(50) NOT NULL, last_name VARCHAR(50) NOT NULL, email VARCHAR(100) UNIQUE, city VARCHAR(50), state VARCHAR(2), joined_at TIMESTAMP DEFAULT now());
CREATE TABLE IF NOT EXISTS orders (order_id SERIAL PRIMARY KEY, customer_id INTEGER REFERENCES customers(customer_id), order_date TIMESTAMP DEFAULT now(), status VARCHAR(20) DEFAULT 'pending', total_amount NUMERIC(10,2));
CREATE TABLE IF NOT EXISTS order_items (item_id SERIAL PRIMARY KEY, order_id INTEGER REFERENCES orders(order_id), product_id INTEGER REFERENCES products(product_id), quantity INTEGER NOT NULL, unit_price NUMERIC(10,2) NOT NULL);
SQL
rt=$(psq stepup_store "select coalesce((select reltuples::bigint from pg_class where oid=to_regclass('support_tickets')),-9)")
sz=$(psq stepup_store "select coalesce(pg_relation_size(to_regclass('support_tickets')),0)")
if [[ "$rt" -ge 0 || "$rt" == "-9" || "$sz" -lt 20000000 ]]; then
  # build the incident: 500k tickets, 450k deleted, no ANALYZE, autovacuum off on the table
  psqf stepup_store <<'SQL' || { say "failed to build support_tickets"; exit 1; }
DROP TABLE IF EXISTS support_tickets;
CREATE TABLE support_tickets (ticket_id SERIAL PRIMARY KEY, customer_id INT NOT NULL, category VARCHAR(20), priority VARCHAR(10), subject TEXT, created_at TIMESTAMP DEFAULT now()) WITH (autovacuum_enabled = false);
CREATE INDEX idx_tickets_customer ON support_tickets(customer_id);
CREATE INDEX idx_tickets_category_priority ON support_tickets(category, priority);
INSERT INTO support_tickets(customer_id, category, priority, subject)
  SELECT 1 + (g::bigint * 7919) % 20000, (array['billing','tech','account','shipping'])[1 + g % 4], (array['low','normal','high','critical'])[1 + g % 4], repeat('s',100)
  FROM generate_series(1,500000) g;
DELETE FROM support_tickets WHERE ticket_id % 10 <> 0;
SQL
else
  say "support_tickets already has no statistics, leaving it as is"
fi
# orders: wipe its statistics too so the planner has no idea about its size
psq stepup_store "UPDATE pg_class SET reltuples = -1, relpages = 0 WHERE oid = 'orders'::regclass" >/dev/null
psq stepup_store "DELETE FROM pg_statistic WHERE starelid = 'orders'::regclass" >/dev/null
psq stepup_store "SELECT pg_stat_reset_single_table_counters('orders'::regclass)" >/dev/null
say ""
say "ALERT: Application performance severely degraded."
say "All modules are slow. Queries that normally take 5ms"
say "are now taking 2-10 seconds."
say "The data cleanup team ran a bulk deletion job last night"
say "to purge old support tickets. No other changes were made."
say "Multiple teams are reporting timeouts."
exit 0
