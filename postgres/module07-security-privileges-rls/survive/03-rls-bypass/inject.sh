#!/usr/bin/env bash
# SUTA survive scenario: module07-security-privileges-rls/03-rls-bypass
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module07-03; mkdir -p "$STATE_DIR"
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
# roles first (their own statement: a failed seed must not skip them), then make sure the
# learner's orders table has the columns this scenario uses (another module may have shaped it)
psq stepup_store "$(cat <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tenant_alpha') THEN CREATE ROLE tenant_alpha LOGIN PASSWORD 'alphapass123'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tenant_beta') THEN CREATE ROLE tenant_beta LOGIN PASSWORD 'betapass123'; END IF;
END $$;
SQL
)" >/dev/null
psq stepup_store "ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_id integer, ADD COLUMN IF NOT EXISTS product_id integer, ADD COLUMN IF NOT EXISTS quantity integer, ADD COLUMN IF NOT EXISTS total_amount numeric(10,2), ADD COLUMN IF NOT EXISTS tenant_id text" >/dev/null
psq stepup_store "$(cat <<'SQL'
INSERT INTO orders (customer_id, product_id, quantity, total_amount, tenant_id) SELECT 1, 1, 1, 10, 'tenant_alpha' FROM generate_series(1,3) WHERE NOT EXISTS (SELECT 1 FROM orders WHERE tenant_id = 'tenant_alpha');
INSERT INTO orders (customer_id, product_id, quantity, total_amount, tenant_id) SELECT 2, 2, 1, 20, 'tenant_beta' FROM generate_series(1,3) WHERE NOT EXISTS (SELECT 1 FROM orders WHERE tenant_id = 'tenant_beta');
GRANT SELECT ON TABLE orders TO tenant_alpha, tenant_beta;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_policy ON orders;
DROP POLICY IF EXISTS tenant_insert_policy ON orders;
DROP POLICY IF EXISTS tenant_update_policy ON orders;
DROP POLICY IF EXISTS rls_gap_policy ON orders;
CREATE POLICY tenant_select_policy ON orders FOR SELECT USING (tenant_id = current_user);
CREATE POLICY tenant_insert_policy ON orders FOR INSERT WITH CHECK (tenant_id = current_user);
CREATE POLICY tenant_update_policy ON orders FOR UPDATE USING (tenant_id = current_user) WITH CHECK (tenant_id = current_user);
CREATE POLICY rls_gap_policy ON orders FOR SELECT USING (true);
SQL
)" >/dev/null && say "orders policies updated"
say "tenant_beta sees rows of: $(psq stepup_store "SET ROLE tenant_beta; SELECT string_agg(DISTINCT tenant_id, ', ') FROM orders")"
say ""
say "ALERT: Security audit found that tenant_beta can see"
say "tenant_alpha orders in stepup_store. RLS is enabled"
say "on the orders table but data isolation is broken."
say "Customers are reporting seeing each other's orders."
exit 0
