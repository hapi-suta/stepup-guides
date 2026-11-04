#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/03-missing-wal-segment
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-03; mkdir -p "$STATE_DIR"
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
REPO=/opt/pgsql/backup/pgbackrest/archive/main
find_seg() { find "$REPO" -type f -name "$1-*" 2>/dev/null | head -1; }
if [[ -s "$STATE_DIR/segment" && -z "$(find_seg "$(cat "$STATE_DIR/segment")")" ]]; then
  say "(WAL segment already missing from the archive)"
else
  psq postgres "select pg_logical_emit_message(true,'suta','a')" >/dev/null
  S1=$(psq postgres "select pg_walfile_name(pg_current_wal_lsn())"); psq postgres "select pg_switch_wal()" >/dev/null
  psq postgres "select pg_logical_emit_message(true,'suta','b')" >/dev/null
  S2=$(psq postgres "select pg_walfile_name(pg_current_wal_lsn())"); psq postgres "select pg_switch_wal()" >/dev/null
  wait_archived "$S2" || { say "archiver did not catch up in 15s"; exit 1; }
  f=$(find_seg "$S1"); [[ -n "$f" ]] || { say "segment $S1 not found in the archive"; exit 1; }
  rm -f "$f" && echo "$S1" > "$STATE_DIR/segment"
fi
say "archived segments: $(find "$REPO" -type f -name '0*-*' 2>/dev/null | wc -l)"
say ""
say "ALERT: High - PITR capability is broken, recovery to certain points is impossible."
say "pgbackrest verify on stanza main is reporting problems with the WAL archive."
exit 0
