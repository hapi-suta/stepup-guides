#!/usr/bin/env bash
# SUTA survive scenario: module06-users-roles-connections/03-max-connections-exhausted
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module06-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
tcp_as() { PGCONNECT_TIMEOUT=5 PGPASSWORD="$2" "$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U "$1" -d "${4:-stepup_store}" -v ON_ERROR_STOP=1 -tAXqc "$3" 2>/dev/null; }
[[ -x "$PGBIN/psql" && -d "$PGDATA" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then
  systemctl reset-failed postgresql-16 >/dev/null 2>&1; systemctl start postgresql-16 >/dev/null 2>&1
  wait_up || { say "PostgreSQL did not start"; exit 1; }
fi
psq postgres "SELECT 1 FROM pg_database WHERE datname = 'stepup_store'" | grep -q 1 || psq postgres "CREATE DATABASE stepup_store" >/dev/null
seed_base() {
  psq postgres "$(cat <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN CREATE ROLE app_user LOGIN CONNECTION LIMIT 20; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'readonly_user') THEN CREATE ROLE readonly_user LOGIN; END IF;
END $$;
ALTER ROLE app_user PASSWORD 'apppass123';
ALTER ROLE readonly_user PASSWORD 'readpass123';
SQL
)" >/dev/null 2>&1 || say "warning: role seed failed"
  psq stepup_store "$(cat <<'SQL'
CREATE TABLE IF NOT EXISTS customers (customer_id serial PRIMARY KEY, first_name text, last_name text, email text);
CREATE TABLE IF NOT EXISTS products (product_id serial PRIMARY KEY, name text, price numeric(10,2));
CREATE TABLE IF NOT EXISTS orders (order_id serial PRIMARY KEY, customer_id int, product_id int, quantity int DEFAULT 1, total_amount numeric(10,2), tenant_id text DEFAULT 'default');
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT 'default';
DO $$ BEGIN
  IF (SELECT count(*) FROM customers) = 0 THEN INSERT INTO customers (first_name, last_name, email) SELECT 'Cust' || g, 'Lab', 'cust' || g || '@example.com' FROM generate_series(1,5) g; END IF;
  IF (SELECT count(*) FROM products) = 0 THEN INSERT INTO products (name, price) SELECT 'Product ' || g, g * 10 FROM generate_series(1,10) g; END IF;
  IF (SELECT count(*) FROM orders) = 0 THEN INSERT INTO orders (customer_id, product_id, quantity, total_amount) SELECT g, g, 1, g * 10 FROM generate_series(1,6) g; END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
GRANT SELECT, INSERT, UPDATE ON orders TO app_user;
GRANT SELECT ON customers, products TO app_user;
GRANT SELECT ON orders, customers, products TO readonly_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_user;
SQL
)" >/dev/null 2>&1 || say "warning: table seed failed"
  say "seeded base roles and tables (stepup_store)"
}
seed_base
cur=$(psq postgres "SHOW max_connections")
if [[ "$cur" != "5" ]]; then
  echo "$cur" > "$STATE_DIR/max_connections.before"
  psq postgres "ALTER SYSTEM SET max_connections = 5" >/dev/null
  systemctl restart postgresql-16 >/dev/null 2>&1
  wait_up || { say "PostgreSQL did not come back"; exit 1; }
fi
# two long sessions take the only non-reserved slots
have=$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE usename = 'readonly_user' AND query LIKE '%pg_sleep(3600)%'" 2>/dev/null)
for _ in $(seq 1 $((2 - ${have:-0}))); do
  setsid nohup env PGPASSWORD=readpass123 "$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U readonly_user -d stepup_store -c "SELECT pg_sleep(3600)" >/dev/null 2>&1 &
done
sleep 3
say "max_connections=$(psq postgres 'SHOW max_connections'), sessions in use: $(psq postgres 'SELECT count(*) FROM pg_stat_activity')"
say "TCP login as app_user:"
PGCONNECT_TIMEOUT=5 PGPASSWORD=apppass123 "$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U app_user -d stepup_store -c "SELECT 1" 2>&1 | head -1
say ""
say "ALERT: PostgreSQL cannot accept new connections."
say "max_connections is set too low (5). With 3 reserved"
say "for superusers, only 2 slots are available for the app."
say "The Pulse dashboard shows 'too many connections'."
exit 0
