#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/08-autovacuum-too-aggressive
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. seed: a table that keeps tripping the 1-row thresholds
psq stepup_store "CREATE TABLE IF NOT EXISTS aggressive_vac_demo (id int PRIMARY KEY, payload text)"
[[ "$(psq stepup_store "SELECT count(*) FROM aggressive_vac_demo")" == "0" ]] && psq stepup_store "INSERT INTO aggressive_vac_demo SELECT g, 'row ' || g FROM generate_series(1,20000) g"
# 2. break: five autovacuum parameters at extreme values (all sighup, reload is enough)
if ! grep -q 'autovacuum_vacuum_cost_limit' "$PGDATA/postgresql.auto.conf"; then
  psq stepup_store "ALTER SYSTEM SET autovacuum_naptime = '1s'"
  psq stepup_store "ALTER SYSTEM SET autovacuum_vacuum_cost_delay = 0"
  psq stepup_store "ALTER SYSTEM SET autovacuum_vacuum_cost_limit = 10000"
  psq stepup_store "ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.001"
  psq stepup_store "ALTER SYSTEM SET autovacuum_vacuum_threshold = 1"
  psq postgres "SELECT pg_reload_conf()" >/dev/null
fi
sleep 2
psq stepup_store "UPDATE aggressive_vac_demo SET payload = payload || 'x' WHERE id <= 5000"
sleep 2
say "Autovacuum workers show up in pg_stat_activity almost every second."
say ""
say "ALERT: Autovacuum is consuming excessive I/O and CPU."
say "autovacuum_naptime=1s, cost_delay=0, cost_limit=10000."
say "Queries are running slower than expected."
say "Autovacuum workers are constantly active."
exit 0
