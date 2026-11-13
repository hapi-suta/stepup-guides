#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/05-pgdata-permissions
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if [[ "$(stat -c %a "$PGDATA")" != "755" || "$(stat -c %U "$PGDATA/postgresql.conf")" != "root" ]]; then
  # record the good state, stop cleanly, loosen the data directory, hand the main config to root
  stat -c '%a %U:%G %n' "$PGDATA" "$PGDATA/postgresql.conf" > "$STATE_DIR/perms_before"
  systemctl stop postgresql-16 >/dev/null 2>&1
  for _ in $(seq 1 20); do pg_up || break; sleep 1; done
  chmod 755 "$PGDATA"
  chown root:root "$PGDATA/postgresql.conf"
fi
systemctl start postgresql-16 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL failed to start after system maintenance."
say "Error: data directory has wrong permissions."
say "Service is DOWN."
exit 0
