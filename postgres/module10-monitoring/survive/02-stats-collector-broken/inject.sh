#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/02-stats-collector-broken
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-02; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. seed: the orders table the runbook queries (only if the learner has none), with some history
if [[ "$(psq stepup_store "SELECT count(*) FROM pg_class WHERE relname='orders' AND relkind='r'")" == "0" ]]; then
  psq stepup_store "CREATE TABLE orders (order_id serial PRIMARY KEY, status text, amount numeric)"
  psq stepup_store "INSERT INTO orders (status, amount) SELECT 'new', g FROM generate_series(1,1000) g"
fi
psq stepup_store "SELECT count(*) FROM orders" >/dev/null
sleep 1
# 2. break: stop activity and counter tracking (both sighup, reload is enough)
psq stepup_store "ALTER SYSTEM SET track_activities = off"
psq stepup_store "ALTER SYSTEM SET track_counts = off"
psq postgres "SELECT pg_reload_conf()" >/dev/null
sleep 2
for _ in 1 2 3; do psq stepup_store "SELECT count(*) FROM orders" >/dev/null; done
say "Dashboards that were fine an hour ago now render empty panels."
say ""
say "ALERT: Monitoring dashboards are showing stale data."
say "pg_stat_activity shows no active queries even during load."
say "pg_stat_user_tables shows zero for seq_scan and idx_scan."
say "The Pulse dashboard Health Check panel shows no activity."
exit 0
