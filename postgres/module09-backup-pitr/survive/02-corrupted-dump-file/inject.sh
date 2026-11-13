#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/02-corrupted-dump-file
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-02; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }

cd /
pbr() { sudo -u postgres pgbackrest "$@"; }
ensure_up() { pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; } || { say "PostgreSQL is not running"; exit 1; }; }
need_pbr() {
  if ! command -v pgbackrest >/dev/null 2>&1 || ! pbr --stanza=main info >"$STATE_DIR/info.out" 2>&1 \
     || ! grep -q 'status: ok' "$STATE_DIR/info.out" || ! grep -qE '(full|diff|incr) backup:' "$STATE_DIR/info.out"; then
    say "PRECONDITION: finish Tutorial 8 (a working pgBackRest stanza 'main' with at least one backup) first"; exit 2
  fi
}
seed_employees() {
  psq stepup_store "create table if not exists employees (id serial primary key, name text, department text, hired_at timestamptz default now())" || return 1
  if [[ "$(psq stepup_store "select count(*) from employees")" == "0" ]]; then
    psq stepup_store "insert into employees (name, department) select 'emp_' || g, (array['engineering','sales','marketing','hr','finance'])[1 + (g % 5)] from generate_series(1,10000) g" || return 1
  fi
}
wait_archived() { local a; for _ in $(seq 1 15); do a=$(psq postgres "select coalesce(last_archived_wal,'') from pg_stat_archiver"); [[ "$a" == "$1" || "$a" > "$1" ]] && return 0; sleep 1; done; return 1; }

ensure_up
D=/opt/pgsql/backup/dumps; F=$D/stepup_store.custom
install -d -o postgres -g postgres "$D"
seed_employees || { say "could not seed employees"; exit 1; }
if [[ -s "$F" ]] && ! sudo -u postgres "$PGBIN/pg_restore" --list "$F" >/dev/null 2>&1; then
  say "(dump already corrupted)"
else
  sudo -u postgres "$PGBIN/pg_dump" -p "$PGPORT" -d stepup_store -Fc -f "$F" || { say "pg_dump failed"; exit 1; }
  printf 'CHAOS-CORRUPT-HDR' | dd of="$F" bs=1 count=17 conv=notrunc 2>/dev/null
  chown postgres:postgres "$F"
fi
say "$(ls -l "$F")"
say ""
say "ALERT: High - Backup integrity compromised, recovery capability degraded."
say "The nightly logical backup of stepup_store failed its restore test."
exit 0
