#!/usr/bin/env bash
# SUTA survive scenario: module11-streaming-replication/07-archive-command-failure
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-sr-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

ARC=/opt/pgsql/archive
[[ -x "$PGBIN/postgres" && -d "$PGDATA" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL did not start"; exit 1; }; }
if [[ "$(psq postgres 'show archive_mode')" != "on" ]]; then
  say "PRECONDITION: finish Tutorial 3 (archive_mode = on and /opt/pgsql/archive) first"; exit 2
fi
mkdir -p "$ARC"; chown postgres:postgres "$ARC"

# 1. lock the archive directory (once), 2. force WAL switches so the archiver fails
if [[ "$(stat -c %a "$ARC")" != "0" ]]; then
  stat -c %a "$ARC" > "$STATE_DIR/archive_mode_before"
  chmod 000 "$ARC"
fi
psq postgres "select pg_switch_wal()" >/dev/null
sleep 2
psq postgres "select pg_switch_wal()" >/dev/null
sleep 5
say "pg_stat_archiver failed_count: $(psq postgres 'select failed_count from pg_stat_archiver')"
say ""
say "ALERT: High - WAL archiving broken, backup chain at risk."
say "pg_stat_archiver reports failed archive attempts on the primary."
exit 0
