#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/01-migration-failed-midway
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module19-01; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
DB=migrate_chaos
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
pg_up || { say "PostgreSQL is not running"; exit 1; }
[[ "$(psq postgres "select count(*) from pg_database where datname='$DB'")" == "1" ]] || sudo -u postgres "$PGBIN/createdb" -p "$PGPORT" "$DB"
psq "$DB" "
CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, description text NOT NULL, success boolean NOT NULL, applied_at timestamp DEFAULT now());
CREATE TABLE IF NOT EXISTS employees (id serial PRIMARY KEY, name text NOT NULL, department text, salary numeric(10,2));
ALTER TABLE employees ADD COLUMN IF NOT EXISTS department_id integer;
CREATE TABLE IF NOT EXISTS departments (id serial PRIMARY KEY, name text UNIQUE NOT NULL, budget numeric(12,2));
ALTER TABLE employees DROP CONSTRAINT IF EXISTS fk_employees_department;
TRUNCATE departments RESTART IDENTITY;
UPDATE employees SET department_id = NULL;
INSERT INTO employees (name, department, salary)
  SELECT * FROM (VALUES ('Alice','Engineering',95000),('Bob','Engineering',90000),('Carol','Sales',70000),('Dave','Sales',65000),('Erin','HR',60000)) v(n,d,s)
  WHERE NOT EXISTS (SELECT 1 FROM employees);
INSERT INTO schema_migrations (version, description, success) VALUES (1,'create_employees',true) ON CONFLICT (version) DO NOTHING;
INSERT INTO schema_migrations (version, description, success) VALUES (2,'add_departments',false)
  ON CONFLICT (version) DO UPDATE SET success = false;
" >/dev/null
say "schema_migrations: $(psq "$DB" "select string_agg(version||'='||success::text, ', ' order by version) from schema_migrations")"
say ""
say "ALERT: The application team reports that migration V2 failed partway through."
say "Some DDL changes were applied but the data migration did not complete. The schema is in an inconsistent state."
exit 0
