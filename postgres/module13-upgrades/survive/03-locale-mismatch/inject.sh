#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/03-locale-mismatch
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
P15=/usr/pgsql-15/bin; D15=/opt/pgsql/data15; D16=/opt/pgsql/data16
psq15() { sudo -u postgres "$P15/psql" -p 5433 -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
up15() { sudo -u postgres "$P15/pg_isready" -q -p 5433; }
start15() { up15 || sudo -u postgres "$P15/pg_ctl" -D "$D15" -l "$PGLOG/pg15.log" -w -t 30 start >/dev/null 2>&1; up15; }
stop15() { up15 && sudo -u postgres "$P15/pg_ctl" -D "$D15" stop -m fast -w -t 30 >/dev/null 2>&1; ! up15; }
need15() {
  if [[ ! -x "$P15/postgres" || ! -f "$D15/PG_VERSION" || ! -f "$D16/PG_VERSION" ]]; then
    say "PRECONDITION: finish Tutorial 2 (PG15 binaries, the PG15 cluster at $D15 and the initdb'd PG16 target at $D16) first"; exit 2
  fi
}

need15
if [[ "$(readlink -f "$D16")" == "$(readlink -f "$PGDATA")" ]]; then say "refusing: $D16 is the production data directory"; exit 1; fi
if [[ -f "$STATE_DIR/injected" && -f "$D16/PG_VERSION" ]]; then
  say "(locale fault already in place)"
else
  if [[ -e "$D16/analyze_new_cluster.sh" ]]; then     # a COMPLETED upgrade; --check output dirs are fine
    say "PRECONDITION: $D16 already holds an upgraded cluster; redo Tutorial 2's initdb of /opt/pgsql/data16 (a fresh target) first"; exit 2
  fi
  start15 || { say "could not start the PG15 cluster on 5433"; exit 1; }
  old=$(psq15 postgres "select datcollate from pg_database where datname='template0'")
  stop15 || { say "could not stop the PG15 cluster"; exit 1; }
  [[ "$old" == "C" ]] && { say "old cluster already uses locale C; cannot build a mismatch"; exit 1; }
  if [[ -f "$D16/postmaster.pid" ]]; then sudo -u postgres "$PGBIN/pg_ctl" -D "$D16" stop -m fast -w >/dev/null 2>&1; fi
  rm -rf "$D16"
  install -d -o postgres -g postgres -m 700 "$D16"
  sudo -u postgres "$PGBIN/initdb" -D "$D16" --encoding=UTF8 --locale=C >"$STATE_DIR/initdb.log" 2>&1 || { say "initdb failed, see $STATE_DIR/initdb.log"; exit 1; }
  echo "$old" > "$STATE_DIR/injected"
fi
say "PG15 cluster is stopped; PG16 production is $(pg_up && echo up || echo down)."
say ""
say "ALERT: pg_upgrade is failing with a locale incompatibility."
say "The new cluster was initialized with a different locale"
say "than the old cluster. The upgrade cannot proceed."
exit 0
