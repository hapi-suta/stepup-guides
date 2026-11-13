#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/05-index-corruption
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-05; mkdir -p "$STATE_DIR"
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
CREATE EXTENSION IF NOT EXISTS amcheck;
CREATE TABLE IF NOT EXISTS chaos5_accounts (id SERIAL PRIMARY KEY, account_num VARCHAR(20) NOT NULL, holder VARCHAR(50), balance NUMERIC(12,2));
SQL
if [[ "$(psq stepup_store "select count(*) from chaos5_accounts")" -lt 5000 ]]; then
  psq stepup_store "TRUNCATE chaos5_accounts; INSERT INTO chaos5_accounts(account_num,holder,balance) SELECT 'ACC-' || lpad(g::text,6,'0'), 'Holder ' || g, (g % 1000) * 10.5 FROM generate_series(1,5000) g"
fi
psq stepup_store "CREATE INDEX IF NOT EXISTS idx_chaos5_account_num ON chaos5_accounts(account_num)"
psq stepup_store "ANALYZE chaos5_accounts"

if psq stepup_store "select bt_index_check('idx_chaos5_account_num')" >/dev/null 2>&1; then
  rel=$(psq stepup_store "select pg_relation_filepath('idx_chaos5_account_num')")
  psq postgres "CHECKPOINT" >/dev/null
  echo "$rel" > "$STATE_DIR/index_file"
  systemctl stop postgresql-16 >/dev/null 2>&1
  # zero block 1 (the first leaf page) of the throwaway index; the heap is untouched
  dd if=/dev/zero of="$PGDATA/$rel" bs=8192 seek=1 count=1 conv=notrunc status=none
  systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
  systemctl start postgresql-16 >/dev/null 2>&1
  wait_up || { say "PostgreSQL did not come back; check the log"; exit 1; }
else
  say "idx_chaos5_account_num is already damaged, leaving it as is"
fi
psq stepup_store "select count(*) from chaos5_accounts where account_num = 'ACC-000001'" >/dev/null 2>&1
say ""
say "ALERT: Queries on the accounts table are returning"
say "intermittent errors. Some lookups by account_num"
say "fail with 'could not read block' or return wrong"
say "results. The application team reports data inconsistencies."
exit 0
