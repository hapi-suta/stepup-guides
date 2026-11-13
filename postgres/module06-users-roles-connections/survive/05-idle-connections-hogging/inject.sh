#!/usr/bin/env bash
# SUTA survive scenario: module06-users-roles-connections/05-idle-connections-hogging
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module06-05; mkdir -p "$STATE_DIR"
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
psq postgres "ALTER ROLE app_user CONNECTION LIMIT -1" >/dev/null
max=$(psq postgres "SHOW max_connections"); res=$(psq postgres "SHOW superuser_reserved_connections")
have=$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend' AND pid <> pg_backend_pid()")
need=$((max - res - have))
say "opening $need idle app_user connections (max_connections=$max)"
for _ in $(seq 1 "$need"); do
  setsid nohup bash -c "(echo 'SELECT 1;'; sleep 3600) | PGPASSWORD=apppass123 $PGBIN/psql -q -h 127.0.0.1 -p $PGPORT -U app_user -d stepup_store >/dev/null 2>&1" >/dev/null 2>&1 &
done
for _ in $(seq 1 15); do
  n=$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE usename = 'app_user' AND state = 'idle'")
  [[ "${n:-0}" -ge $((need - 2)) ]] && break; sleep 1
done
say "idle app_user connections: $n"
say "TCP login as app_user:"
PGCONNECT_TIMEOUT=5 PGPASSWORD=apppass123 "$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U app_user -d stepup_store -c "SELECT 1" 2>&1 | head -1
say ""
say "ALERT: Connection pool exhausted. New connections failing."
say "Many idle connections from app_user are holding all available slots."
say "The Pulse dashboard shows errors. New connections from the app cannot be established."
exit 0
