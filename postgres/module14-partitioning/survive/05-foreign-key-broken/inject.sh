#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/05-foreign-key-broken
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
psqf() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXq; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and would not start"; exit 1; }; }
reload() { psq postgres "select pg_reload_conf()" >/dev/null; sleep 1; }
# seed: stepup_store database (idempotent)
if [[ "$(psq postgres "select count(*) from pg_database where datname='stepup_store'")" != "1" ]]; then
  sudo -u postgres "$PGBIN/createdb" -p "$PGPORT" stepup_store && say "created database stepup_store"
fi
have=$(psq stepup_store "select count(*) from pg_class where relname='chaos5_orders'")
att=$(psq stepup_store "select count(*) from pg_inherits where inhparent=to_regclass('chaos5_orders') and inhrelid=to_regclass('chaos5_orders_2024_02')")
if [[ "$have" == "0" ]]; then
  psqf stepup_store <<'SQL'
CREATE TABLE chaos5_orders (id INT NOT NULL, order_date DATE NOT NULL, customer_id INT, status VARCHAR(20), total_amount NUMERIC(10,2), region VARCHAR(50), PRIMARY KEY (id, order_date)) PARTITION BY RANGE (order_date);
CREATE TABLE chaos5_orders_2024_01 PARTITION OF chaos5_orders FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE chaos5_orders_2024_02 PARTITION OF chaos5_orders FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE chaos5_orders_2024_03 PARTITION OF chaos5_orders FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
INSERT INTO chaos5_orders SELECT g, DATE '2024-01-01' + (g % 90), 1 + g % 100, 'pending', (g % 500) + 0.5, 'West' FROM generate_series(1,3000) g;
CREATE TABLE chaos5_line_items (line_id SERIAL PRIMARY KEY, order_id INT NOT NULL, order_date DATE NOT NULL, product_name VARCHAR(100), quantity INT, FOREIGN KEY (order_id, order_date) REFERENCES chaos5_orders (id, order_date));
INSERT INTO chaos5_line_items (order_id, order_date, product_name, quantity) SELECT id, order_date, 'Product ' || id, 1 FROM chaos5_orders WHERE id % 6 = 0;
SQL
  att=1
fi
if [[ "$att" == "1" ]]; then
  # a plain DETACH is refused while line items reference the partition, so the "maintenance job"
  # drops the FK, detaches, and re-adds the FK as NOT VALID (existing rows are not re-checked)
  psqf stepup_store <<'SQL'
BEGIN;
DO $$ DECLARE n text; BEGIN
  SELECT conname INTO n FROM pg_constraint WHERE conrelid='chaos5_line_items'::regclass AND contype='f' AND confrelid='chaos5_orders'::regclass AND conparentid=0;
  EXECUTE format('ALTER TABLE chaos5_line_items DROP CONSTRAINT %I', n);
  ALTER TABLE chaos5_orders DETACH PARTITION chaos5_orders_2024_02;
  EXECUTE format('ALTER TABLE chaos5_line_items ADD CONSTRAINT %I FOREIGN KEY (order_id, order_date) REFERENCES chaos5_orders (id, order_date) NOT VALID', n);
END $$;
COMMIT;
SQL
else
  say "chaos5_orders_2024_02 is already detached"
fi
say "line items: $(psq stepup_store 'select count(*) from chaos5_line_items')"
say ""
say "ALERT: Application errors on the orders system."
say "Some queries on line_items are returning FK violation"
say "errors. A partition maintenance job detached February's"
say "partition but there are line_items referencing orders"
say "in that month. The detached partition still exists as"
say "a standalone table but is no longer part of the"
say "partitioned hierarchy."
exit 0
