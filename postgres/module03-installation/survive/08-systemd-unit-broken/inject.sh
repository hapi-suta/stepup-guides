#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/08-systemd-unit-broken
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module03-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
DROP=/etc/systemd/system/postgresql-16.service.d; OV="$DROP/override.conf"
mkdir -p "$DROP"
if ! grep -q 'data-WRONG' "$OV" 2>/dev/null; then
  [[ -f "$OV" ]] && cp -p "$OV" "$OV.suta-orig"
  if grep -q '^[[:space:]]*Environment=.*PGDATA=' "$OV" 2>/dev/null; then
    sed -i -E 's|^([[:space:]]*Environment=.*PGDATA=)[^[:space:]"]*|\1/opt/pgsql/data-WRONG|' "$OV"
  else
    printf '\n[Service]\nEnvironment=PGDATA=/opt/pgsql/data-WRONG\n' >> "$OV"
  fi
  systemctl daemon-reload
  systemctl restart postgresql-16 >/dev/null 2>&1 || true
  sleep 2
  systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
fi
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL 16 failed to start after a routine maintenance window."
say "An on-call engineer made a systemd configuration change; the service won't come up."
say "Nobody touched postgresql.conf or the data directory directly."
exit 0
