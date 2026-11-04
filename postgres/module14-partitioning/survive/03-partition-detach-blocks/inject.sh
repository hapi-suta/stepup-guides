#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/03-partition-detach-blocks
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-03; mkdir -p "$STATE_DIR"
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
if [[ "$(psq stepup_store "select count(*) from pg_class where relname='orders_chaos3'")" == "0" ]]; then
  psqf stepup_store <<'SQL'
CREATE TABLE orders_chaos3 (order_id INT NOT NULL, customer_id INT, order_date DATE NOT NULL, status VARCHAR(20), total_amount NUMERIC(10,2), region VARCHAR(50)) PARTITION BY RANGE (order_date);
CREATE TABLE orders_chaos3_2024_01 PARTITION OF orders_chaos3 FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE orders_chaos3_2024_02 PARTITION OF orders_chaos3 FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE orders_chaos3_2024_03 PARTITION OF orders_chaos3 FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
INSERT INTO orders_chaos3 SELECT g, 1 + g % 100, DATE '2024-01-01' + (g % 91), 'pending', (g % 500) + 0.5, 'West' FROM generate_series(1,3000) g;
SQL
fi
# put the partition back if an earlier run of this scenario was already fixed
if [[ "$(psq stepup_store "select count(*) from pg_inherits where inhparent='orders_chaos3'::regclass and inhrelid=to_regclass('orders_chaos3_2024_01')")" == "0" ]]; then
  psq stepup_store "ALTER TABLE orders_chaos3 ATTACH PARTITION orders_chaos3_2024_01 FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')"
fi
held() { psq stepup_store "select count(*) from pg_locks l join pg_class c on c.oid=l.relation where c.relname='orders_chaos3' and l.mode='AccessExclusiveLock' and l.granted"; }
if [[ "$(held)" == "0" ]]; then
  # session 1: the plain DETACH inside an open transaction (holds the lock and never finishes)
  setsid nohup bash -c "( echo 'BEGIN;'; echo 'ALTER TABLE orders_chaos3 DETACH PARTITION orders_chaos3_2024_01;'; sleep 7200 ) | sudo -u postgres $PGBIN/psql -p $PGPORT -d stepup_store -X -q >/dev/null 2>&1" >/dev/null 2>&1 &
  for _ in $(seq 1 10); do [[ "$(held)" != "0" ]] && break; sleep 1; done
  # session 2: an application SELECT that queues behind it
  setsid nohup sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d stepup_store -X -q -c "SELECT COUNT(*) FROM orders_chaos3" >/dev/null 2>&1 &
  sleep 2
else
  say "a session already holds the lock on orders_chaos3"
fi
say "sessions waiting on locks: $(psq stepup_store "select count(*) from pg_stat_activity where wait_event_type='Lock'")"
say ""
say "ALERT: A DETACH PARTITION operation is holding an ACCESS EXCLUSIVE lock on orders_chaos3."
say "All SELECTs and INSERTs on orders_chaos3 are queued."
say "Application is reporting timeouts."
say "Diagnose and resolve the blocking operation."
exit 0
