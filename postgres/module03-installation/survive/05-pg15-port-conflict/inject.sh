#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/05-pg15-port-conflict
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module03-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

PG15BIN=/usr/pgsql-15/bin; PG15DATA=/opt/pgsql/data15
if [[ ! -x "$PG15BIN/postgres" || ! -f "$PG15DATA/PG_VERSION" || ! -f /usr/lib/systemd/system/postgresql-15.service ]]; then
  say "PRECONDITION: finish Tutorial 2 (multi-version install: PostgreSQL 15 on port 5433) first"; exit 2
fi
CONF="$PG15DATA/postgresql.conf"
pg15_port() { sudo -u postgres "$PG15BIN/postgres" -D "$PG15DATA" -C port 2>/dev/null; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL 16 would not start"; exit 1; }; fi
if [[ "$(pg15_port)" != "5432" ]]; then
  cp -p "$CONF" "$CONF.suta-orig"
  systemctl stop postgresql-15 >/dev/null 2>&1
  if grep -qE '^[[:space:]]*port[[:space:]]*=' "$CONF"; then
    sed -i -E 's/^([[:space:]]*)port[[:space:]]*=[[:space:]]*[0-9]+/\1port = 5432/' "$CONF"
  else
    printf '\nport = 5432\n' >> "$CONF"
  fi
fi
systemctl restart postgresql-15 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-15 >/dev/null 2>&1 || true
say "postgresql-16: $(systemctl is-active postgresql-16)   postgresql-15: $(systemctl is-active postgresql-15)"
say ""
say "ALERT: PostgreSQL 15 will not start. PostgreSQL 16 is still running on port 5432."
say "A junior DBA changed the PostgreSQL 15 port configuration."
exit 0
