#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/01-connection-exhaustion
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-01; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi

# 1. count the free non-reserved slots; fill them with long pg_sleep sessions (idempotent: free slots = 0 means done)
MAXC=$(psq postgres "SELECT setting::int FROM pg_settings WHERE name='max_connections'")
RESV=$(psq postgres "SELECT setting::int FROM pg_settings WHERE name='superuser_reserved_connections'")
CUR=$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE backend_type='client backend'")
NEED=$((MAXC - RESV - CUR - 1))
say "max_connections=$MAXC reserved=$RESV in use=$CUR"
if [[ $NEED -gt 0 ]]; then
  echo "$NEED" > "$STATE_DIR/sessions_started"
  # one sudo, many background psql sessions, fully detached from this shell
  sudo -u postgres env PGBIN="$PGBIN" PGPORT="$PGPORT" NEED="$NEED" bash -c '
    for _ in $(seq 1 "$NEED"); do
      setsid nohup "$PGBIN/psql" -p "$PGPORT" -d labdb -tAXqc "SELECT pg_sleep(3600)" >/dev/null 2>&1 &
    done'
  sleep 5
fi
say "connections now: $(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE backend_type='client backend'")"
say ""
say "ALERT: PostgreSQL connection pool exhausted."
say "Applications reporting 'FATAL: too many connections'."
exit 0
