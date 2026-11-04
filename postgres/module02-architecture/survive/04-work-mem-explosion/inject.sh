#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/04-work-mem-explosion
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi

# 1. modest sort table (about 10MB), 2. work_mem = 2GB cluster-wide, 3. 15 sessions that sort it and then hold the connection
psq labdb "CREATE TABLE IF NOT EXISTS chaos_sort_data AS SELECT g AS id, md5(g::text) || md5((g * 7)::text) AS payload FROM generate_series(1, 100000) g"
WM=$(psq postgres "SELECT setting FROM pg_settings WHERE name='work_mem'")
if [[ "$WM" != "2097152" ]]; then
  echo "$WM" > "$STATE_DIR/work_mem_kb_before"
  psq postgres "ALTER SYSTEM SET work_mem = '2GB'" && psq postgres "SELECT pg_reload_conf()" >/dev/null
  sleep 2
fi
RUN=$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%chaos_sort_data%' AND state = 'active' AND pid <> pg_backend_pid()")
if [[ "${RUN:-0}" -lt 10 ]]; then
  sudo -u postgres env PGBIN="$PGBIN" PGPORT="$PGPORT" bash -c '
    for _ in $(seq 1 15); do
      setsid nohup "$PGBIN/psql" -p "$PGPORT" -d labdb -tAXqc "SELECT count(*) FROM (SELECT * FROM chaos_sort_data ORDER BY payload) s, pg_sleep(3600)" >/dev/null 2>&1 &
    done'
  sleep 4
fi
say "memory available: $(awk '/MemAvailable/ {printf "%d MB", $2/1024}' /proc/meminfo)"
say ""
say "ALERT: System memory critically low."
say "OOM killer may activate."
say "15 sessions consuming excessive memory."
say "work_mem set to 2GB - each sort operation uses up to 2GB."
exit 0
