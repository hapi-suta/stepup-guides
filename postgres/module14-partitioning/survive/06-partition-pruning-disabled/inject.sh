#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/06-partition-pruning-disabled
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-06; mkdir -p "$STATE_DIR"
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
if [[ "$(psq stepup_store "select count(*) from pg_class where relname='chaos6_sales'")" == "0" ]]; then
  psqf stepup_store <<'SQL'
CREATE TABLE chaos6_sales (sale_id BIGSERIAL, sale_date DATE NOT NULL, product VARCHAR(50), amount NUMERIC(10,2)) PARTITION BY RANGE (sale_date);
DO $$ DECLARE m int; BEGIN
  FOR m IN 1..12 LOOP
    EXECUTE format('CREATE TABLE chaos6_sales_2024_%s PARTITION OF chaos6_sales FOR VALUES FROM (%L) TO (%L)', lpad(m::text,2,'0'), make_date(2024,m,1), (make_date(2024,m,1) + interval '1 month')::date);
  END LOOP;
END $$;
INSERT INTO chaos6_sales (sale_date, product, amount) SELECT DATE '2024-01-01' + (g % 366), 'Product ' || (g % 20), (g % 900) + 0.99 FROM generate_series(1,24000) g;
ANALYZE chaos6_sales;
SQL
fi
psq postgres "ALTER SYSTEM SET enable_partition_pruning = off" >/dev/null
reload
say ""
say "ALERT: Queries on the sales table that filter by date"
say "are scanning all 12 partitions instead of just the"
say "relevant month. Query performance has degraded 12x."
say "A configuration change was made recently during a"
say "troubleshooting session."
exit 0
