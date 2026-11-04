#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/09-full-cluster-recovery
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-09; mkdir -p "$STATE_DIR"
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

ensure_up; need_pbr
D=/opt/pgsql/data; DEAD=/opt/pgsql/data.destroyed
if [[ -d "$DEAD" && ! -f "$D/PG_VERSION" ]]; then
  say "(cluster already destroyed)"
else
  [[ -d "$DEAD" ]] && { say "refusing: $DEAD exists from an earlier run; remove it first"; exit 1; }
  need_kb=$(( $(du -sk "$D" | cut -f1) + 1048576 )); free_kb=$(df -Pk /opt/pgsql | awk 'NR==2{print $4}')
  (( free_kb > need_kb )) || { say "not enough free space under /opt/pgsql for a restore"; exit 1; }
  seed_employees || { say "could not seed employees"; exit 1; }
  pbr --stanza=main --type=incr --start-fast backup >"$STATE_DIR/backup.log" 2>&1 || { say "backup failed, see $STATE_DIR/backup.log"; exit 1; }
  psq postgres "select pg_switch_wal()" >/dev/null
  wait_archived "$(psq postgres 'select pg_walfile_name(pg_current_wal_lsn()-1)')" >/dev/null
  psq stepup_store "select count(*) from employees" > "$STATE_DIR/employees_count"
  systemctl stop postgresql-16 >/dev/null 2>&1
  pg_up && { say "PostgreSQL did not stop"; exit 1; }
  mv "$D" "$DEAD" || { say "could not move the data directory"; systemctl start postgresql-16; exit 1; }
  systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
fi
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: Critical - Complete database outage, all data unavailable."
say "PostgreSQL is down on NODE1 and every database is unreachable."
exit 0
