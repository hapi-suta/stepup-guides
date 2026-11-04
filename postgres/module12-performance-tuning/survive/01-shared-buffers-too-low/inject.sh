#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/01-shared-buffers-too-low
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-01; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
psqf() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXq; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and would not start"; exit 1; }; }
reload() { psq postgres "select pg_reload_conf()" >/dev/null; sleep 1; }
CONF="$PGDATA/postgresql.conf"; AUTO="$PGDATA/postgresql.auto.conf"
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

cur_kb=$(psq postgres "select setting::bigint*8 from pg_settings where name='shared_buffers'")
if grep -q '# chaos injection' "$CONF" && [[ -n "$cur_kb" && "$cur_kb" -lt 1024 ]]; then
  say "shared_buffers is already tiny, leaving it as is"
else
  cp -p "$CONF" "$STATE_DIR/postgresql.conf.before"
  [[ -f "$AUTO" ]] && cp -p "$AUTO" "$STATE_DIR/postgresql.auto.conf.before"
  sed -i '/# chaos injection/d' "$CONF"
  sed -i -E '/^[[:space:]]*shared_buffers[[:space:]]*=/ s/^/#suta-orig /' "$CONF"
  [[ -f "$AUTO" ]] && sed -i -E '/^[[:space:]]*shared_buffers[[:space:]]*=/d' "$AUTO"
  for sz in 128kB 256kB 512kB 1MB 4MB; do
    sed -i '/# chaos injection/d' "$CONF"
    printf 'shared_buffers = %s   # chaos injection\n' "$sz" >> "$CONF"
    systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
    if systemctl restart postgresql-16 >/dev/null 2>&1 && wait_up; then break; fi
  done
  systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
fi
pg_up || { say "PostgreSQL did not come back; check the log"; exit 1; }
# generate some cold-cache reads so pg_statio shows misses
psq stepup_store "select count(*) from orders o join customers c using (customer_id)" >/dev/null 2>&1
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: Database is extremely slow."
say "Every query is slower than expected."
say "The Pulse cache hit ratio is near 0%."
say "A junior DBA 'optimized' the server to save memory."
exit 0
