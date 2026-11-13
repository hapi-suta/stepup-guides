#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/10-monitoring-query-overhead
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-10; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. break: every logging knob at maximum (all sighup, reload is enough)
psq postgres "ALTER SYSTEM SET log_statement = 'all'"
psq postgres "ALTER SYSTEM SET log_min_duration_statement = 0"
psq postgres "ALTER SYSTEM SET log_duration = on"
psq postgres "ALTER SYSTEM SET log_lock_waits = on"
psq postgres "ALTER SYSTEM SET log_parser_stats = on"
psq postgres "ALTER SYSTEM SET log_planner_stats = on"
psq postgres "ALTER SYSTEM SET log_executor_stats = on"
psq postgres "SELECT pg_reload_conf()" >/dev/null
sleep 2
for _ in 1 2 3 4 5; do psq stepup_store "SELECT 1" >/dev/null; done
newest=$(ls -t "$PGLOG"/postgresql-* 2>/dev/null | head -1)
[[ -n "$newest" ]] && say "$(ls -lh "$newest")"
say ""
say "ALERT: Monitoring configuration is causing overhead."
say "log_statement='all' logs every single query."
say "log_min_duration_statement=0 logs every query's duration."
say "Parser, planner, and executor stats logging is enabled."
say "Log files are growing rapidly and disk I/O is elevated."
exit 0
