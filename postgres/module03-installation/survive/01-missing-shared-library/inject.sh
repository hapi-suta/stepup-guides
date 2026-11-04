#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/01-missing-shared-library
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module03-01; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
LIB=/usr/pgsql-16/lib/pg_stat_statements.so; CONF="$PGDATA/postgresql.conf"
if [[ ! -f "$LIB" && ! -f "$LIB.bak" ]]; then
  say "PRECONDITION: finish Tutorial 4 (extensions: it installs postgresql16-contrib) first"; exit 2
fi
if [[ -f "$LIB" ]]; then
  if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
  psq labdb "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" >/dev/null 2>&1
  # make sure the config asks for the library at startup (the runbook greps postgresql.conf for it)
  if ! sudo -u postgres "$PGBIN/postgres" -D "$PGDATA" -C shared_preload_libraries 2>/dev/null | grep -q pg_stat_statements; then
    cp -p "$CONF" "$STATE_DIR/postgresql.conf.before"
    printf "\nshared_preload_libraries = 'pg_stat_statements'\n" >> "$CONF"
  fi
  mv "$LIB" "$LIB.bak"
fi
systemctl restart postgresql-16 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL failed to start. Service is DOWN."
say "shared_preload_libraries could not load a required library."
say "A developer reports pg_stat_statements stopped working after a recent OS patching window."
exit 0
