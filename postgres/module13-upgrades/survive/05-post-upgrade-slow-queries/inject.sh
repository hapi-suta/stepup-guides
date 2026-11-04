#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/05-post-upgrade-slow-queries
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }

if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running"; exit 1; }; fi
psq stepup_store "create table if not exists chaos13_customers (id integer primary key, name text not null) with (autovacuum_enabled = false)" || exit 1
psq stepup_store "create table if not exists chaos13_orders (id serial primary key, customer_id integer, status varchar(20), amount numeric(10,2)) with (autovacuum_enabled = false)" || exit 1
psq stepup_store "alter table chaos13_customers set (autovacuum_enabled = false); alter table chaos13_orders set (autovacuum_enabled = false)" || exit 1
if [[ "$(psq stepup_store "select count(*) from chaos13_customers")" == "0" ]]; then
  psq stepup_store "insert into chaos13_customers select i, 'Customer ' || i from generate_series(1,5000) i" || exit 1
fi
if [[ "$(psq stepup_store "select count(*) from chaos13_orders")" == "0" ]]; then
  psq stepup_store "insert into chaos13_orders (customer_id, status, amount) select (i % 5000) + 1, case when i % 4 = 0 then 'pending' when i % 4 = 1 then 'shipped' when i % 4 = 2 then 'delivered' else 'cancelled' end, (i % 500) + 0.99 from generate_series(1,50000) i" || exit 1
fi
# wipe statistics the way a fresh pg_upgrade leaves them
psq stepup_store "delete from pg_statistic where starelid in ('chaos13_customers'::regclass, 'chaos13_orders'::regclass)" || exit 1
psq stepup_store "select pg_stat_reset_single_table_counters('chaos13_customers'::regclass), pg_stat_reset_single_table_counters('chaos13_orders'::regclass)" >/dev/null
say "stepup_store: chaos13_customers and chaos13_orders loaded; PostgreSQL $(psq postgres 'show server_version') is up."
say ""
say "ALERT: After a major version upgrade, queries are"
say "running 10-50x slower than before. EXPLAIN shows"
say "wildly wrong row estimates. The DBA ran pg_upgrade"
say "but forgot to run ANALYZE on the new cluster."
exit 0
