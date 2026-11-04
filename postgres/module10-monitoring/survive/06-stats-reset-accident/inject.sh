#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/06-stats-reset-accident
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# precondition: pg_stat_statements is built by Tutorial 2 (needs shared_preload_libraries + restart)
if [[ "$(psq postgres "SHOW shared_preload_libraries")" != *pg_stat_statements* ]]; then
  say "PRECONDITION: finish Tutorial 2 (pg_stat_statements in shared_preload_libraries + CREATE EXTENSION) first"; exit 2
fi
psq stepup_store "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" || { say "PRECONDITION: finish Tutorial 2 (pg_stat_statements extension) first"; exit 2; }
# 1. seed: a user table with real scan history to lose
if [[ "$(psq stepup_store "SELECT count(*) FROM pg_class WHERE relname='orders' AND relkind='r'")" == "0" ]]; then
  psq stepup_store "CREATE TABLE orders (order_id serial PRIMARY KEY, status text, amount numeric)"
  psq stepup_store "INSERT INTO orders (status, amount) SELECT 'new', g FROM generate_series(1,1000) g"
fi
for _ in 1 2 3; do psq stepup_store "SELECT count(*) FROM orders" >/dev/null; done
sleep 2
# 2. break: the three resets the runbook diagnoses
psq stepup_store "SELECT pg_stat_reset()" >/dev/null
psq stepup_store "SELECT pg_stat_statements_reset()" >/dev/null
psq stepup_store "SELECT pg_stat_reset_shared('bgwriter')" >/dev/null
say "Every dashboard panel that plots a counter dropped to zero at the same minute."
say ""
say "ALERT: All monitoring data is gone."
say "pg_stat_user_tables shows zero counts everywhere."
say "pg_stat_statements is empty."
say "Someone ran pg_stat_reset(). Monitoring is blind."
exit 0
