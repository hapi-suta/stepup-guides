#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/06-rollback-impossible
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module19-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
DB=rollback_chaos
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
pg_up || { say "PostgreSQL is not running"; exit 1; }
[[ "$(psq postgres "select count(*) from pg_database where datname='$DB'")" == "1" ]] || sudo -u postgres "$PGBIN/createdb" -p "$PGPORT" "$DB"
psq "$DB" "
CREATE TABLE IF NOT EXISTS customers (id serial PRIMARY KEY, name text NOT NULL, email text);
CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, description text, applied_at timestamp DEFAULT now());
INSERT INTO customers (name, email)
  SELECT * FROM (VALUES ('Alice Johnson','alice@example.com'),('Bob Smith','bob@example.com'),('Charlie Brown','charlie@example.com'),('Diana Prince','diana@example.com'),('Eve Wilson','eve@example.com')) v(n,e)
  WHERE NOT EXISTS (SELECT 1 FROM customers);
DELETE FROM schema_migrations WHERE version >= 3;
INSERT INTO schema_migrations (version, description) VALUES (1,'create_customers'),(2,'drop_loyalty_points') ON CONFLICT (version) DO NOTHING;
ALTER TABLE customers DROP COLUMN IF EXISTS loyalty_points;
" >/dev/null
printf '1500\n890\n2300\n450\n3100\n' >/tmp/loyalty_points_backup.txt
chmod 644 /tmp/loyalty_points_backup.txt
say "customers columns: $(psq "$DB" "select string_agg(column_name, ', ' order by ordinal_position) from information_schema.columns where table_name='customers'")"
say ""
say "ALERT: The application team ran a migration that dropped the loyalty_points column from the customers table."
say "The column contained customer loyalty point balances. No pre-migration backup was taken."
exit 0
