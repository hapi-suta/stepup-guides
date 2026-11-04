#!/usr/bin/env bash
# SUTA survive scenario: module11-streaming-replication/08-pg-hba-lockout
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-sr-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -d "$PGDATA" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL did not start"; exit 1; }; }
if [[ "$(psq postgres 'select pg_is_in_recovery()')" != "f" ]]; then
  say "PRECONDITION: run this on the primary (pg-primary); finish Tutorial 3 first"; exit 2
fi
HBA=$(psq postgres "show hba_file")
RX='^[[:space:]]*(local|host[a-z]*)[[:space:]]+replication[[:space:]]'

# 1. back up pg_hba.conf, 2. disable every replication rule (once), 3. reload, 4. drop the walsender
if grep -Eq "$RX" "$HBA"; then
  [[ -f "$HBA.bak" ]] || cp -p "$HBA" "$HBA.bak"
  sed -Ei "s/($RX)/#chaos# \1/" "$HBA"
fi
psq postgres "select pg_reload_conf()" >/dev/null
psq postgres "select pg_terminate_backend(pid) from pg_stat_activity where backend_type='walsender'" >/dev/null
sleep 8
say "connected standbys: $(psq postgres 'select count(*) from pg_stat_replication')"
say ""
say "ALERT: High - Standby cannot replicate, increasing data loss risk."
say "pg_stat_replication on the primary shows no connected standby."
exit 0
