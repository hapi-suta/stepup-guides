#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/01-default-partition-full
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-01; mkdir -p "$STATE_DIR"
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
if [[ "$(psq stepup_store "select coalesce((select count(*) from pg_class where relname='orders_chaos_default'),0)")" == "1" \
   && "$(psq stepup_store "select count(*) from orders_chaos_default")" -ge 5000 ]]; then
  say "orders_chaos already has its rows stuck in the default partition"
else
  psqf stepup_store <<'SQL'
DROP TABLE IF EXISTS orders_chaos CASCADE;
CREATE TABLE orders_chaos (order_id INT NOT NULL, customer_id INT, order_date DATE NOT NULL, status VARCHAR(20), total_amount NUMERIC(10,2), region VARCHAR(50)) PARTITION BY RANGE (order_date);
CREATE TABLE orders_chaos_2020_01 PARTITION OF orders_chaos FOR VALUES FROM ('2020-01-01') TO ('2020-02-01');
CREATE TABLE orders_chaos_2020_02 PARTITION OF orders_chaos FOR VALUES FROM ('2020-02-01') TO ('2020-03-01');
CREATE TABLE orders_chaos_default PARTITION OF orders_chaos DEFAULT;
INSERT INTO orders_chaos SELECT g, 1 + g % 100, DATE '2024-01-01' + (g % 91), 'pending', (g % 500) + 0.5, (array['West','East','North','South'])[1 + g % 4] FROM generate_series(1,5000) g;
ANALYZE orders_chaos;
SQL
  echo 5000 > "$STATE_DIR/rows"
fi
say "rows in orders_chaos: $(psq stepup_store 'select count(*) from orders_chaos')"
say ""
say "ALERT: The orders_chaos table was just deployed."
say "All inserts are going to the default partition."
say "Queries are doing full scans - partition pruning is broken."
say "Fix the partition bounds and redistribute the data."
exit 0
