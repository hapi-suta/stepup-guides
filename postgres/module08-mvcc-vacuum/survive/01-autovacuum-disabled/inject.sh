#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/01-autovacuum-disabled
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-01; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. seed: the table the runbook names, with live rows (idempotent)
[[ -f "$STATE_DIR/autovacuum.before" ]] || psq postgres "SHOW autovacuum" > "$STATE_DIR/autovacuum.before"
psq stepup_store "CREATE TABLE IF NOT EXISTS avac_neglected (id int PRIMARY KEY, payload text)"
if [[ "$(psq stepup_store "SELECT count(*) FROM avac_neglected")" == "0" ]]; then
  psq stepup_store "INSERT INTO avac_neglected SELECT g, 'row ' || g FROM generate_series(1,15000) g"
fi
# 2. break: autovacuum off globally via ALTER SYSTEM, then create dead tuples that stay
psq stepup_store "ALTER SYSTEM SET autovacuum = off"
psq postgres "SELECT pg_reload_conf()" >/dev/null
sleep 2
dead=$(psq stepup_store "SELECT COALESCE(max(n_dead_tup),0) FROM pg_stat_user_tables WHERE relname='avac_neglected'")
if [[ "${dead:-0}" -lt 1000 ]]; then
  psq stepup_store "UPDATE avac_neglected SET payload = payload || ' v2' WHERE id <= 10000"
fi
sleep 2
say "Dead tuples are climbing in stepup_store; no autovacuum worker has run for a while."
say ""
say "ALERT: Dead tuples accumulating across all tables."
say "Autovacuum has been disabled. No automatic cleanup is running."
say "Tables in stepup_store show growing dead tuple counts."
exit 0
