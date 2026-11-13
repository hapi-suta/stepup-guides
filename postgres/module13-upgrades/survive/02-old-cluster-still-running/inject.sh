#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/02-old-cluster-still-running
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-02; mkdir -p "$STATE_DIR"
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
start15 || { say "could not start the PG15 cluster on 5433"; exit 1; }
sudo -u postgres "$P15/pg_ctl" -D "$D16" status >/dev/null 2>&1 && sudo -u postgres "$PGBIN/pg_ctl" -D "$D16" stop -m fast -w >/dev/null 2>&1
say "PG15 (port 5433) accepting connections: $(up15 && echo yes || echo no)"
say "PG16 production (port 5432): $(pg_up && echo up || echo down)"
say ""
say "ALERT: pg_upgrade is failing to start."
say "The error message indicates the old cluster is still"
say "running. The upgrade cannot proceed."
exit 0
