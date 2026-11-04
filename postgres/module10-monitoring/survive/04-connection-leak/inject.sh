#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/04-connection-leak
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

leaked() { psq postgres "SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%pg_sleep(3600)%' AND pid <> pg_backend_pid()"; }
# 1. break part one: a tight connection limit (postmaster setting, so restart)
if [[ "$(psq postgres "SHOW max_connections")" != "20" ]]; then
  [[ -f "$STATE_DIR/max_connections.before" ]] || psq postgres "SHOW max_connections" > "$STATE_DIR/max_connections.before"
  psq postgres "ALTER SYSTEM SET max_connections = 20"
  systemctl restart postgresql-16 >/dev/null 2>&1
  wait_up || { say "PostgreSQL did not come back after restart"; exit 1; }
fi
# 2. break part two: 16 sessions that connect and sleep for an hour
have=$(leaked)
for _ in $(seq 1 $(( 16 - ${have:-0} ))); do
  nohup setsid sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d stepup_store -tAXqc "SELECT pg_sleep(3600);" </dev/null >/dev/null 2>&1 &
done
for _ in $(seq 1 15); do [[ "$(leaked)" -ge 16 ]] && break; sleep 1; done
say "Application logs show FATAL: sorry, too many clients already."
say ""
say "ALERT: Application reports \"too many connections\" errors."
say "New application connections are being refused."
say "max_connections is nearly exhausted."
exit 0
