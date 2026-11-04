#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/10-parallel-workers-disabled
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-10; mkdir -p "$STATE_DIR"
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
psqf stepup_store <<'SQL'
CREATE TABLE IF NOT EXISTS chaos10_transactions (txn_id SERIAL PRIMARY KEY, txn_type VARCHAR(10) NOT NULL, amount NUMERIC(12,2) NOT NULL, note TEXT);
SQL
if [[ "$(psq stepup_store "select count(*) from chaos10_transactions")" -lt 400000 ]]; then
  psq stepup_store "TRUNCATE chaos10_transactions; INSERT INTO chaos10_transactions(txn_type,amount,note) SELECT CASE WHEN g % 2 = 0 THEN 'credit' ELSE 'debit' END, (g % 10000) / 7.0, repeat('t',40) FROM generate_series(1,400000) g; ANALYZE chaos10_transactions;"
fi
psq postgres "ALTER SYSTEM SET max_parallel_workers_per_gather = 0" >/dev/null
psq postgres "ALTER SYSTEM SET max_parallel_workers = 0" >/dev/null
psq postgres "ALTER SYSTEM SET max_parallel_maintenance_workers = 0" >/dev/null
reload
say ""
say "ALERT: Aggregate queries on large tables are running"
say "much slower than expected. The server has multiple CPU"
say "cores but only one core is active during queries."
say "A configuration review was done recently to 'reduce"
say "resource usage' during a maintenance window."
exit 0
