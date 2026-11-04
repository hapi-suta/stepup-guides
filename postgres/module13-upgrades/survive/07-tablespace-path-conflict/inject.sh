#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/07-tablespace-path-conflict
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }

TS=/opt/pgsql/tablespaces/chaos7_archive; MOVED=/opt/pgsql/tablespaces/chaos7_archive_moved
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running"; exit 1; }; fi
if [[ ! -d "$TS" && -d "$MOVED" ]]; then
  say "(tablespace directory already moved)"
else
  install -d -o postgres -g postgres -m 700 /opt/pgsql/tablespaces "$TS"
  if [[ "$(psq stepup_store "select count(*) from pg_tablespace where spcname='chaos7_tbs'")" == "0" ]]; then
    psq stepup_store "create tablespace chaos7_tbs location '$TS'" || exit 1
  fi
  psq stepup_store "create table if not exists chaos7_archive (id integer primary key, note text) tablespace chaos7_tbs" || exit 1
  if [[ "$(psq stepup_store "select count(*) from chaos7_archive")" == "0" ]]; then
    psq stepup_store "insert into chaos7_archive select i, 'archived row ' || i from generate_series(1,5000) i" || exit 1
  fi
  psq stepup_store "checkpoint" >/dev/null
  systemctl stop postgresql-16 >/dev/null 2>&1
  mv "$TS" "$MOVED" || { say "could not move the tablespace directory"; systemctl start postgresql-16; exit 1; }
  systemctl start postgresql-16 >/dev/null 2>&1; wait_up || say "PostgreSQL did not come back in 30s"
fi
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: Queries on the archive table are failing with"
say "'could not open file' errors. The table was stored"
say "in a custom tablespace. During a storage migration,"
say "the tablespace directory may have been moved or renamed."
exit 0
