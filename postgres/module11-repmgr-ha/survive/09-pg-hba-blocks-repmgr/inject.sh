#!/usr/bin/env bash
# SUTA survive scenario: module11-repmgr-ha/09-pg-hba-blocks-repmgr
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-repmgr-09; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -d "$PGDATA" && -s /etc/repmgr/16/repmgr.conf ]] || { say "PRECONDITION: finish Tutorial 4 (repmgr on this node) first"; exit 2; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL did not start"; exit 1; }; }
if [[ "$(psq postgres 'select pg_is_in_recovery()')" != "f" ]]; then
  say "PRECONDITION: run this on the current primary"; exit 2
fi
HBA="$PGDATA/pg_hba.conf"
RX='^[[:space:]]*(local|host[a-z]*)[[:space:]]+replication[[:space:]]'

# 1. keep the good file as pg_hba.conf.backup, 2. disable the replication rules (once)
#    (repmgr database rules stay, so repmgrd on the standbys still sees this primary)
if grep -Eq "$RX" "$HBA"; then
  [[ -f "$HBA.backup" ]] || cp -p "$HBA" "$HBA.backup"
  sed -Ei "s/($RX)/#chaos# \1/" "$HBA"
fi
psq postgres "select pg_reload_conf()" >/dev/null
psq postgres "select pg_terminate_backend(pid) from pg_stat_activity where backend_type='walsender'" >/dev/null
sleep 8
say "connected standbys: $(psq postgres 'select count(*) from pg_stat_replication')"
say ""
say "ALERT: Critical - Standbys cannot stream from this primary."
say "pg_stat_replication is empty and the standbys log connection errors."
exit 0
