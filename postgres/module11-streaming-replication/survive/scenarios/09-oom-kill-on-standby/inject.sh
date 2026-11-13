#!/usr/bin/env bash
# SUTA-NODE: 2
# SUTA survive scenario: module11-streaming-replication/09-oom-kill-on-standby
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-sr-09; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -d "$PGDATA" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if [[ ! -f "$PGDATA/standby.signal" ]]; then
  say "PRECONDITION: finish Tutorial 4 (the standby build on pg-standby) first"; exit 2
fi

# SIGKILL the postmaster (what the OOM killer does); skip when it is already down
if [[ "$(systemctl is-active postgresql-16)" == "active" ]]; then
  systemctl kill --kill-whom=main -s SIGKILL postgresql-16 >/dev/null 2>&1
  sleep 4
fi
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say "pg_isready: $(sudo -u postgres "$PGBIN/pg_isready" -p "$PGPORT")"
say ""
say "ALERT: High - No replication redundancy, standby is down."
say "PostgreSQL on the standby (pg-standby) stopped unexpectedly."
exit 0
