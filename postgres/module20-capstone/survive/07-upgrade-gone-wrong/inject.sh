#!/usr/bin/env bash
# SUTA survive scenario: module20-capstone/07-upgrade-gone-wrong
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module20-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
DB=appdb; ST=/tmp/stepup-capstone-07-state.env
if [[ ! -d "$PGDATA" ]] || ! systemctl cat postgresql-16 >/dev/null 2>&1; then say "postgresql-16 is not installed at $PGDATA"; exit 1; fi
if [[ -e "$PGDATA/pg_wal.broken" && ! -e "$PGDATA/pg_wal" ]]; then
  say "(already injected)"
else
  pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
  if [[ "$(psq "$DB" "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname in ('orders','customers')" 2>/dev/null)" != "2" ]]; then
    say "PRECONDITION: finish Tutorial 1 (production deployment: appdb with app.customers and app.orders) first"; exit 2
  fi
  # the proof of integrity: row counts before the "upgrade", plus the library version
  { echo "ORDERS_COUNT=$(psq "$DB" 'select count(*) from app.orders')"; echo "CUSTOMERS_COUNT=$(psq "$DB" 'select count(*) from app.customers')"; echo "PG_MAJOR=16"; } >"$ST"
  cp "$ST" "$STATE_DIR/state.env"
  psq postgres "CHECKPOINT" >/dev/null
  systemctl stop postgresql-16 >/dev/null 2>&1
  mv "$PGDATA/pg_wal" "$PGDATA/pg_wal.broken"
  mkdir -p /opt/pgsql/data_new && echo "17" >/opt/pgsql/data_new/PG_VERSION && chown -R postgres:postgres /opt/pgsql/data_new
fi
systemctl start postgresql-16 >/dev/null 2>&1
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: Critical - Database down, old cluster damaged, new cluster incomplete."
say "An upgrade attempt was abandoned halfway and PostgreSQL will not start."
exit 0
