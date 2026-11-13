#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/07-pitr-wrong-target
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-07; mkdir -p "$STATE_DIR"
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
ST="$STATE_DIR/stepup-07-state.env"
bad_n=$(psq stepup_store "select count(*) from pitr_marker where state='BAD_STATE'" 2>/dev/null); good_n=$(psq stepup_store "select count(*) from pitr_marker where state='GOOD_STATE'" 2>/dev/null)
if [[ -f "$ST" && "${bad_n:-0}" -ge 1 && "${good_n:-1}" == "0" ]]; then
  say "(pitr_marker already in the bad state)"
else
  need_pbr
  psq stepup_store "drop table if exists pitr_marker" || exit 1
  psq stepup_store "create table pitr_marker (id serial primary key, state text not null, created_at timestamp default now())" || exit 1
  pbr --stanza=main --type=incr --start-fast backup >"$STATE_DIR/backup.log" 2>&1 || { say "backup failed, see $STATE_DIR/backup.log"; exit 1; }
  sleep 2
  psq stepup_store "insert into pitr_marker (state) values ('GOOD_STATE')" || exit 1
  sleep 2
  ts() { psq postgres "select to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') || '+00'"; }
  correct=$(ts); sleep 2
  psq stepup_store "delete from pitr_marker where state='GOOD_STATE'; insert into pitr_marker (state) values ('BAD_STATE'),('BAD_STATE'),('BAD_STATE')" || exit 1
  psq postgres "select pg_switch_wal()" >/dev/null
  wait_archived "$(psq postgres 'select pg_walfile_name(pg_current_wal_lsn()-1)')" >/dev/null
  printf 'CORRECT_TARGET="%s"\n' "$correct" > "$ST"; cp -p "$ST" /tmp/stepup-07-state.env
  future=$(psq postgres "select to_char((clock_timestamp() + interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') || '+00'")
  printf 'Recovery notes (handover)\nPlanned PITR target time: %s\nAction: restore with --type=time to this target.\n' "$future" > /tmp/pitr-recovery-notes.txt
  chmod 644 /tmp/pitr-recovery-notes.txt
fi
say "pitr_marker rows: $(psq stepup_store "select string_agg(state, ',' order by id) from pitr_marker")"
say ""
say "ALERT: High - Recovery went past the desired point, data state is incorrect."
say "The pitr_marker table in stepup_store is missing its GOOD_STATE row."
exit 0
