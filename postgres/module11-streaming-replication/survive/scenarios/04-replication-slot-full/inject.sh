#!/usr/bin/env bash
# SUTA survive scenario: module11-streaming-replication/04-replication-slot-full
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-sr-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -d "$PGDATA" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL did not start"; exit 1; }; }
if [[ "$(psq postgres 'select pg_is_in_recovery()')" != "f" ]]; then
  say "PRECONDITION: run this on the primary (pg-primary); finish Tutorial 3 first"; exit 2
fi

# 1. create a slot nobody consumes (once), 2. generate WAL so the primary has to keep it
if [[ -z "$(psq postgres "select 1 from pg_replication_slots where slot_name='standby2_slot'")" ]]; then
  psq postgres "select pg_create_physical_replication_slot('standby2_slot', true)" >/dev/null
  psq labdb "CREATE TABLE IF NOT EXISTS chaos_wal_filler(payload text)"
  psq labdb "INSERT INTO chaos_wal_filler SELECT repeat('x', 400) FROM generate_series(1, 150000)" >/dev/null
  psq labdb "TRUNCATE chaos_wal_filler"
  psq postgres "select pg_switch_wal()" >/dev/null
  psq postgres "CHECKPOINT"
fi
say "pg_wal size: $(du -sh "$PGDATA/pg_wal" | cut -f1)"
say "disk: $(df -h "$PGDATA" | awk 'NR==2 {print $5 " used on " $6}')"
say ""
say "ALERT: High - Disk exhaustion risk on primary."
say "The WAL directory on the primary is growing and is not being recycled."
exit 0
