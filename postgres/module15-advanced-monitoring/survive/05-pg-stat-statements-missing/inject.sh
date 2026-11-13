#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/05-pg-stat-statements-missing
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module15-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
CONF="$PGDATA/postgresql.conf"
[[ -x "$PGBIN/postgres" && -f "$CONF" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
psq stepup_store "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" >/dev/null 2>&1
eff() { sudo -u postgres "$PGBIN/postgres" -D "$PGDATA" -C shared_preload_libraries 2>/dev/null; }
if eff | grep -q pg_stat_statements; then
  [[ -f "$STATE_DIR/postgresql.conf.before" ]] || cp -p "$CONF" "$STATE_DIR/postgresql.conf.before"
  sed -i -E "/^[[:space:]]*shared_preload_libraries/{s/pg_stat_statements,?//; s/,'/'/; s/,,/,/}" "$CONF"
  if eff | grep -q pg_stat_statements; then
    new=$(eff | sed -E 's/pg_stat_statements,?//; s/,$//')
    psq postgres "ALTER SYSTEM SET shared_preload_libraries = '$new'" >/dev/null
  fi
  systemctl restart postgresql-16 >/dev/null 2>&1
  wait_up
fi
say "shared_preload_libraries = '$(psq postgres 'show shared_preload_libraries' 2>/dev/null)'"
say ""
say "ALERT: No query statistics available - pg_stat_statements queries fail."
say "Monitoring continues but query performance data is gone."
exit 0
