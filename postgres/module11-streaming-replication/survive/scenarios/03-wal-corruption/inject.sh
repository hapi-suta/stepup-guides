#!/usr/bin/env bash
# SUTA-NODE: 2
# SUTA survive scenario: module11-streaming-replication/03-wal-corruption
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-sr-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -d "$PGDATA" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if [[ ! -f "$PGDATA/standby.signal" ]]; then
  say "PRECONDITION: finish Tutorial 4 (the standby build on pg-standby) first"; exit 2
fi

# 1. stop the standby cleanly, 2. rename the WAL segment its checkpoint needs (once)
if ls "$PGDATA"/pg_wal/*.corrupt >/dev/null 2>&1; then
  say "(a renamed WAL segment is already in place)"
else
  systemctl stop postgresql-16 >/dev/null 2>&1
  seg=$(sudo -u postgres "$PGBIN/pg_controldata" "$PGDATA" | awk -F: '/REDO WAL file/ {gsub(/[ \t]/,"",$2); print $2}')
  if [[ -z "$seg" || ! -f "$PGDATA/pg_wal/$seg" ]]; then
    say "could not find the standby's redo WAL segment (got '${seg:-none}')"; systemctl start postgresql-16 >/dev/null 2>&1; exit 1
  fi
  printf '%s\n' "$seg" > "$STATE_DIR/segment"
  mv "$PGDATA/pg_wal/$seg" "$PGDATA/pg_wal/$seg.corrupt"
fi

# 3. try to bring the standby back so the learner sees the failure
systemctl start postgresql-16 >/dev/null 2>&1 || true
sleep 3
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say "pg_isready: $(sudo -u postgres "$PGBIN/pg_isready" -p "$PGPORT")"
say ""
say "ALERT: High - Standby replication is broken, no HA protection."
say "PostgreSQL on the standby (pg-standby) is not accepting connections and the primary shows no streaming standby."
exit 0
