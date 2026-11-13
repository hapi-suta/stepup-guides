#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/08-partition-constraint-violation
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-08; mkdir -p "$STATE_DIR"
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
have=$(psq stepup_store "select count(*) from pg_class where relname='chaos8_invoices'")
q2=$(psq stepup_store "select count(*) from pg_class where relname='chaos8_invoices_2024_q2'")
if [[ "$have" == "0" || "$q2" != "0" ]]; then
  psqf stepup_store <<'SQL'
DROP TABLE IF EXISTS chaos8_invoices CASCADE;
CREATE TABLE chaos8_invoices (id BIGSERIAL, invoice_date DATE NOT NULL, customer_name VARCHAR(100), amount NUMERIC(10,2), status VARCHAR(20) DEFAULT 'pending') PARTITION BY RANGE (invoice_date);
CREATE TABLE chaos8_invoices_2024_q1 PARTITION OF chaos8_invoices FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');
CREATE TABLE chaos8_invoices_2024_q3 PARTITION OF chaos8_invoices FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');
INSERT INTO chaos8_invoices (invoice_date, customer_name, amount) SELECT (array[DATE '2024-01-15', DATE '2024-08-15'])[1 + g % 2] + (g % 20), 'Customer ' || g, (g % 900) + 0.5 FROM generate_series(1,400) g;
SQL
else
  say "chaos8_invoices already lacks the Q2 and Q4 partitions"
fi
say "failed application insert:"
psq stepup_store "INSERT INTO chaos8_invoices (invoice_date, customer_name, amount) VALUES ('2024-04-15', 'Test Customer', 100.00)" 2>&1 | head -2
say ""
say "ALERT: Invoice inserts are failing with:"
say "ERROR: no partition of relation \"chaos8_invoices\" found for row"
say "The application is trying to insert April 2024"
say "invoices but they are being rejected. Q1 and Q3"
say "work fine. Q2 and Q4 have no partitions."
say "There is no default partition to catch overflow."
exit 0
