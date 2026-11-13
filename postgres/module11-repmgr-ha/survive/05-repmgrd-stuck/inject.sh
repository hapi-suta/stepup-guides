#!/usr/bin/env bash
# SUTA survive scenario: module11-repmgr-ha/05-repmgrd-stuck
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module11-repmgr-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

CONF=/etc/repmgr/16/repmgr.conf
if [[ ! -x /usr/pgsql-16/bin/repmgrd ]] || ! systemctl cat repmgr-16 >/dev/null 2>&1; then
  say "PRECONDITION: finish Tutorial 7 (the repmgr-16 systemd service) first"; exit 2
fi
if [[ ! -s "$CONF" && ! -s "$CONF.backup" ]]; then
  say "PRECONDITION: finish Tutorial 4 (repmgr.conf on this node) first"; exit 2
fi

# 1. keep a good copy as repmgr.conf.backup, 2. stop repmgrd, 3. empty the config (once)
if [[ -s "$CONF" ]]; then
  [[ -s "$CONF.backup" ]] || cp -p "$CONF" "$CONF.backup"
  systemctl stop repmgr-16 >/dev/null 2>&1
  : > "$CONF"
fi
systemctl start repmgr-16 >/dev/null 2>&1 || true
sleep 3
systemctl reset-failed repmgr-16 >/dev/null 2>&1 || true
say "systemctl is-active repmgr-16: $(systemctl is-active repmgr-16)"
say "systemctl is-active postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: Critical - No automatic failover available."
say "repmgrd is not running on this node and will not start."
exit 0
