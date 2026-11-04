#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/01-postgresql-conf-syntax-error
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module04-01; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

CONF="$PGDATA/postgresql.conf"
[[ -x "$PGBIN/postgres" && -f "$CONF" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }

# 1. break: append one line with invalid syntax (once), 2. restart so the service fails
if ! grep -qF 'work_mem = 64MB extra_garbage' "$CONF"; then
  cp -p "$CONF" "$STATE_DIR/postgresql.conf.before"
  printf '\n# chaos injection - bad syntax\nwork_mem = 64MB extra_garbage\n' >> "$CONF"
fi
systemctl restart postgresql-16 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL failed to start. Service is DOWN."
say "A colleague edited postgresql.conf to tune memory settings"
say "and now the database will not start."
exit 0
