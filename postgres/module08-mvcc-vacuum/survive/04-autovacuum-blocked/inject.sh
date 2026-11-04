#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/04-autovacuum-blocked
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

holder_pid() { psq postgres "SELECT pid FROM pg_stat_activity WHERE query LIKE '%pg_sleep(3601)%' AND pid <> pg_backend_pid() LIMIT 1"; }
if [[ -z "$(holder_pid)" ]]; then
  # 1. seed: 10000 rows, autovacuum off on the table so only the manual VACUUM matters
  psq stepup_store "DROP TABLE IF EXISTS blocked_vacuum_demo"
  psq stepup_store "CREATE TABLE blocked_vacuum_demo (id int PRIMARY KEY, payload text)"
  psq stepup_store "ALTER TABLE blocked_vacuum_demo SET (autovacuum_enabled = false)"
  psq stepup_store "INSERT INTO blocked_vacuum_demo SELECT g, 'row ' || g FROM generate_series(1,10000) g"
  # 2. break: a repeatable-read session takes a snapshot and sleeps inside its transaction
  nohup setsid sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d stepup_store -tAXqc \
    "BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM blocked_vacuum_demo; SELECT pg_sleep(3601);" </dev/null >/dev/null 2>&1 &
  for _ in $(seq 1 10); do [[ -n "$(holder_pid)" ]] && break; sleep 1; done
  # 3. dead tuples that VACUUM cannot remove while the snapshot lives
  psq stepup_store "DELETE FROM blocked_vacuum_demo WHERE id % 2 = 0"
  sleep 2
fi
say "VACUUM on blocked_vacuum_demo finishes but the dead tuple count does not go down."
say ""
say "ALERT: Dead tuples in blocked_vacuum_demo are not being cleaned up."
say "VACUUM runs but cannot remove tuples."
say "A long-running transaction is holding back cleanup."
say "Identify and terminate the blocking transaction."
exit 0
