#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/01-logging-disabled
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-01; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# break: logging_collector off via ALTER SYSTEM (postmaster setting, so restart)
if [[ "$(psq postgres "SHOW logging_collector")" != "off" ]]; then
  psq postgres "ALTER SYSTEM SET logging_collector = off"
  systemctl restart postgresql-16 >/dev/null 2>&1
  wait_up || { say "PostgreSQL did not come back after restart"; exit 1; }
  date +%s > "$STATE_DIR/injected_at"
fi
[[ -f "$STATE_DIR/injected_at" ]] || date +%s > "$STATE_DIR/injected_at"
psq stepup_store "SELECT 1" >/dev/null
say "The newest file in /opt/pgsql/log has not changed since the last restart."
say ""
say "ALERT: PostgreSQL logs have stopped."
say "The on-call engineer cannot find any recent log entries."
say "No slow query data, no error messages, nothing."
say "Something changed in the configuration."
exit 0
