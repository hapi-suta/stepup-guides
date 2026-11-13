#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/07-shared-preload-crash
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
AUTO="$PGDATA/postgresql.auto.conf"
if ! grep -q 'pg_fake_monitoring_lib' "$AUTO"; then
  pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }
  # 1. break: append a library that does not exist to shared_preload_libraries
  cur=$(psq postgres "SHOW shared_preload_libraries")
  [[ -f "$STATE_DIR/spl.before" ]] || printf '%s\n' "$cur" > "$STATE_DIR/spl.before"
  if [[ -n "$cur" ]]; then new="$cur,pg_fake_monitoring_lib"; else new="pg_fake_monitoring_lib"; fi
  psq postgres "ALTER SYSTEM SET shared_preload_libraries = '$new'"
fi
# 2. restart so the service fails to come back
systemctl restart postgresql-16 >/dev/null 2>&1 || true
sleep 3
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL failed to start."
say "The server was restarted and did not come back up."
say "systemctl status shows the service is not running."
say "Something in the configuration is preventing startup."
exit 0
