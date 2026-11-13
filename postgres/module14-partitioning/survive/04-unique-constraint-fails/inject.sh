#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/04-unique-constraint-fails
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-04; mkdir -p "$STATE_DIR"
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
have=$(psq stepup_store "select count(*) from pg_class where relname='orders_chaos4'")
uq=$(psq stepup_store "select count(*) from pg_constraint where conrelid=to_regclass('orders_chaos4') and contype in ('u','p')")
if [[ "$have" == "0" || "$uq" != "0" ]]; then
  psqf stepup_store <<'SQL'
DROP TABLE IF EXISTS orders_chaos4 CASCADE;
CREATE TABLE orders_chaos4 (order_id INT NOT NULL, customer_id INT, order_date DATE NOT NULL, status VARCHAR(20), total_amount NUMERIC(10,2), region VARCHAR(50)) PARTITION BY RANGE (order_date);
CREATE TABLE orders_chaos4_2024_01 PARTITION OF orders_chaos4 FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE orders_chaos4_2024_02 PARTITION OF orders_chaos4 FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE orders_chaos4_2024_03 PARTITION OF orders_chaos4 FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
INSERT INTO orders_chaos4 SELECT g, 1 + g % 100, DATE '2024-01-01' + (g % 91), 'pending', (g % 500) + 0.5, 'West' FROM generate_series(1,3000) g;
SQL
else
  say "orders_chaos4 already has no unique constraint"
fi
say "attempting the developer's change:"
psq stepup_store "ALTER TABLE orders_chaos4 ADD CONSTRAINT uq_chaos4_order_id UNIQUE (order_id)" 2>&1 | head -2
say ""
say "ALERT: Developer request - add UNIQUE(order_id) to orders_chaos4."
say "All attempts are failing with:"
say "ERROR: unique constraint on partitioned table must include all partitioning columns"
say "Diagnose the constraint design issue and implement a working uniqueness strategy."
exit 0
