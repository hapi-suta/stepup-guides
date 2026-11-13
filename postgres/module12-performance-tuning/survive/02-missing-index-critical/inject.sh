#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/02-missing-index-critical
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-02; mkdir -p "$STATE_DIR"
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
has_idx() { psq stepup_store "select count(*) from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=any(i.indkey) where i.indrelid='orders'::regclass and a.attname='order_id' and i.indisunique"; }

if [[ "$(has_idx)" != "0" ]]; then
  # seed a big enough orders table that a seq scan on order_id hurts
  n=$(psq stepup_store "select count(*) from orders")
  if [[ "$n" -lt 300000 ]]; then
    echo "$n" > "$STATE_DIR/orders_rows_before"
    psq stepup_store "INSERT INTO customers(first_name,last_name,email,city,state) SELECT 'Seed','Customer','seed@example.com','Austin','TX' WHERE NOT EXISTS (SELECT 1 FROM customers)"
    psq stepup_store "INSERT INTO orders(customer_id,order_date,status,total_amount) SELECT c.ids[1 + g % array_length(c.ids,1)], now() - (g % 365) * interval '1 day', (array['pending','shipped','delivered','cancelled'])[1 + g % 4], (g % 5000) / 10.0 FROM generate_series(1,300000) g CROSS JOIN (SELECT array_agg(customer_id) AS ids FROM customers) c"
  fi
  # the "migration": drop every constraint on orders (primary key and its index go with it)
  psqf stepup_store <<'SQL'
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT conname FROM pg_constraint WHERE conrelid='orders'::regclass AND contype IN ('p','u','f','c') LOOP
    EXECUTE format('ALTER TABLE orders DROP CONSTRAINT %I CASCADE', r.conname);
  END LOOP;
END $$;
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
ANALYZE orders;
SQL
else
  say "orders already has no unique index on order_id, leaving it as is"
fi
say "orders rows: $(psq stepup_store 'select count(*) from orders')"
say ""
say "ALERT: Orders page loading very slowly."
say "Lookups by order ID are timing out in the application."
say "The development team ran a migration script earlier today."
say "Something may have gone wrong."
exit 0
