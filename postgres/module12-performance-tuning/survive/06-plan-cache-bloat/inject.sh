#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/06-plan-cache-bloat
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-06; mkdir -p "$STATE_DIR"
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
CREATE TABLE IF NOT EXISTS chaos6_events (id SERIAL PRIMARY KEY, status VARCHAR(20) NOT NULL, payload TEXT);
CREATE INDEX IF NOT EXISTS idx_chaos6_status ON chaos6_events(status);
SQL
if [[ "$(psq stepup_store "select count(*) from chaos6_events")" -lt 5000 ]]; then
  psq stepup_store "TRUNCATE chaos6_events; INSERT INTO chaos6_events(status,payload) SELECT CASE WHEN g % 100 = 0 THEN 'pending' ELSE 'processed' END, repeat('e',300) FROM generate_series(1,5000) g; ANALYZE chaos6_events;"
fi
psq postgres "ALTER SYSTEM SET plan_cache_mode = 'force_generic_plan'" >/dev/null
reload
say ""
say "ALERT: The events query is slow for 'pending' status"
say "(only 50 rows) but fast for 'processed' (4950 rows)."
say "The planner is using a generic plan that does not"
say "consider the actual parameter value."
say "A developer set plan_cache_mode to fix a 'plan"
say "instability' issue but made things worse."
exit 0
