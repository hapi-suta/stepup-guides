#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/06-missing-extension-package
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module03-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
if rpm -q postgresql16-contrib >/dev/null 2>&1; then
  # make CREATE EXTENSION fail for real: drop pgcrypto from labdb first, then remove the package (no restart: the server keeps running)
  psq labdb "DROP EXTENSION IF EXISTS pgcrypto" >/dev/null 2>&1
  rpm -q postgresql16-contrib > "$STATE_DIR/removed_package"
  rpm -e postgresql16-contrib >/dev/null 2>&1 || { say "could not remove postgresql16-contrib"; exit 1; }
fi
say "postgresql-16 service: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: CREATE EXTENSION pgcrypto is failing in the application (Severity MEDIUM)."
say "The PostgreSQL 16 server is running, but extensions stopped working after a recent OS patching window."
exit 0
