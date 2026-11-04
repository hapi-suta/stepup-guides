#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/08-checkpoint-storm
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. break: three checkpoint parameters at storm values (all sighup, reload is enough)
psq postgres "ALTER SYSTEM SET checkpoint_completion_target = 0.1"
psq postgres "ALTER SYSTEM SET max_wal_size = '32MB'"
psq postgres "ALTER SYSTEM SET checkpoint_timeout = 30"
psq postgres "SELECT pg_reload_conf()" >/dev/null
sleep 2
# 2. generate WAL so wal-triggered checkpoints actually happen (about 100 MB of WAL)
psq stepup_store "CREATE TABLE IF NOT EXISTS checkpoint_storm_demo (id int PRIMARY KEY, payload text)"
psq stepup_store "INSERT INTO checkpoint_storm_demo SELECT g, md5(g::text) || md5((g+1)::text) FROM generate_series(1,300000) g ON CONFLICT DO NOTHING"
psq stepup_store "UPDATE checkpoint_storm_demo SET payload = md5(payload)"
psq stepup_store "UPDATE checkpoint_storm_demo SET payload = md5(payload)"
say "Checkpoints requested: $(psq postgres "SELECT checkpoints_req FROM pg_stat_bgwriter")"
say ""
say "ALERT: Excessive checkpoints detected."
say "pg_stat_bgwriter shows high requested checkpoint counts."
say "Checkpoints are happening every few seconds."
say "Write performance is degraded due to constant flushing."
exit 0
