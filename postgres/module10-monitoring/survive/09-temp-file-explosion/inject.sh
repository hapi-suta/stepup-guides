#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/09-temp-file-explosion
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-09; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. seed: the table the runbook sorts
psq stepup_store "CREATE TABLE IF NOT EXISTS temp_explosion_a (id serial PRIMARY KEY, val int)"
[[ "$(psq stepup_store "SELECT count(*) FROM temp_explosion_a")" == "0" ]] && psq stepup_store "INSERT INTO temp_explosion_a (val) SELECT (random()*1000000)::int FROM generate_series(1,50000)"
psq stepup_store "ANALYZE temp_explosion_a"
# 2. break: tiny work_mem, no temp file limit, no temp file logging (all sighup/user level, reload is enough)
psq postgres "ALTER SYSTEM SET work_mem = '256kB'"
psq postgres "ALTER SYSTEM SET temp_file_limit = -1"
psq postgres "ALTER SYSTEM SET log_temp_files = -1"
psq postgres "SELECT pg_reload_conf()" >/dev/null
sleep 2
# 3. make the spill visible in pg_stat_database
for _ in 1 2 3 4 5 6; do psq stepup_store "SELECT count(*) FROM (SELECT val FROM temp_explosion_a ORDER BY val) s" >/dev/null; done
say "Temp files created since stats reset: $(psq stepup_store "SELECT temp_files FROM pg_stat_database WHERE datname='stepup_store'")"
say ""
say "ALERT: Excessive temp files on disk."
say "temp_file_limit is -1 (unlimited) - no safety net."
say "work_mem is 256kB - every sort and hash spills to disk."
say "Temp file logging is disabled - no visibility into which queries create them."
say "Disk space in the data directory is growing unexpectedly."
exit 0
