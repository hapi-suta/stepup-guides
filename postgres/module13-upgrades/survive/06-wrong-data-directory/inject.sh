#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/06-wrong-data-directory
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }

CONF="$PGDATA/postgresql.conf"
[[ -x "$PGBIN/postgres" && -f "$CONF" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! grep -qF "chaos injection" "$CONF" || ! grep -qF "data_directory = '/opt/pgsql/data_OLD_v15'" "$CONF"; then
  cp -p "$CONF" "$CONF.suta-orig"
  printf "\ndata_directory = '/opt/pgsql/data_OLD_v15'\t# chaos injection\n" >> "$CONF"
fi
systemctl restart postgresql-16 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL failed to start after a scheduled"
say "maintenance window. The service exits immediately."
say "The DBA team was reconfiguring paths after an upgrade"
say "from PG 15 to PG 16 and may have set a wrong path."
exit 0
