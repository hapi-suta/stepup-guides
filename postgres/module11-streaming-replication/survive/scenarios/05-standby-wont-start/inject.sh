#!/usr/bin/env bash
# SUTA-NODE: 2
# SUTA survive scenario: module11-streaming-replication/05-standby-wont-start
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-sr-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

AUTO="$PGDATA/postgresql.auto.conf"
[[ -x "$PGBIN/postgres" && -f "$AUTO" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if [[ ! -f "$PGDATA/standby.signal" ]]; then
  say "PRECONDITION: finish Tutorial 4 (the standby build on pg-standby) first"; exit 2
fi

# 1. keep a copy of the working file, 2. point primary_conninfo at a dead endpoint (once)
if ! grep -qF 'port=5499' "$AUTO"; then
  cp -p "$AUTO" "$AUTO.suta-orig"
  sed -i '/^primary_conninfo/d' "$AUTO"
  printf "primary_conninfo = 'host=127.0.0.1 port=5499 user=replicator application_name=standby1'\n" >> "$AUTO"
fi
systemctl restart postgresql-16 >/dev/null 2>&1 || true
sleep 4
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say "pg_isready: $(sudo -u postgres "$PGBIN/pg_isready" -p "$PGPORT")"
say ""
say "ALERT: High - No replication redundancy."
say "The standby (pg-standby) is not receiving WAL from the primary."
exit 0
