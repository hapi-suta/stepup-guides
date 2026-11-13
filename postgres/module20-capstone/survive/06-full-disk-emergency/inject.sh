#!/usr/bin/env bash
# SUTA survive scenario: module20-capstone/06-full-disk-emergency
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module20-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
DB=appdb
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
pg_up || { say "PostgreSQL is not running"; exit 1; }
if [[ "$(psq "$DB" "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname='customers'" 2>/dev/null)" != "1" ]]; then
  say "PRECONDITION: finish Tutorial 1 (production deployment: appdb with app.customers) first"; exit 2
fi
# 1. filler files (capped: the root filesystem is never allowed below 3 GB free)
mkdir -p /opt/pgsql/log /opt/pgsql/backup
avail_mb=$(df -Pm /opt/pgsql | awk 'NR==2{print $4}')
each=$(( (avail_mb - 3072) / 4 )); (( each > 256 )) && each=256
if (( each >= 16 )); then
  for f in /tmp/filler_disk.dat /opt/pgsql/log/filler_1.dat /opt/pgsql/log/filler_2.dat /opt/pgsql/backup/filler_1.dat; do
    [[ -f "$f" ]] || { fallocate -l "${each}M" "$f" 2>/dev/null || dd if=/dev/zero of="$f" bs=1M count="$each" status=none; }
  done
  chown postgres:postgres /opt/pgsql/log/filler_*.dat /opt/pgsql/backup/filler_1.dat 2>/dev/null
fi
# 2. inactive replication slot that retains WAL, then generate WAL behind it
[[ "$(psq postgres "select count(*) from pg_replication_slots where slot_name='leak_slot_capstone'")" == "1" ]] || \
  psq postgres "SELECT pg_create_physical_replication_slot('leak_slot_capstone', true)" >/dev/null
# 3. filler table and filler customer rows
psq "$DB" "CREATE TABLE IF NOT EXISTS app.disk_filler (id serial PRIMARY KEY, payload text)" >/dev/null
[[ "$(psq "$DB" "select count(*) from app.disk_filler")" != "0" ]] || \
  psq "$DB" "INSERT INTO app.disk_filler (payload) SELECT repeat(md5(g::text), 20) FROM generate_series(1,40000) g" >/dev/null
[[ "$(psq "$DB" "select count(*) from app.customers where email like 'diskfill%@capstone.lab'")" != "0" ]] || \
  psq "$DB" "INSERT INTO app.customers (email, full_name) SELECT 'diskfill'||g||'@capstone.lab', 'Disk Filler '||g FROM generate_series(1,20000) g" >/dev/null
psq postgres "CHECKPOINT" >/dev/null
say "filesystem holding /opt/pgsql:"; df -h /opt/pgsql | tail -1
say "slot leak_slot_capstone retains: $(psq postgres "select pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) from pg_replication_slots where slot_name='leak_slot_capstone'")"
say ""
say "ALERT: Critical - PostgreSQL may stop accepting writes or crash."
say "Disk usage on the database server is climbing and free space is nearly gone."
exit 0
