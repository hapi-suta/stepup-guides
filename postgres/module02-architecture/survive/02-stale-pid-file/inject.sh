#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/02-stale-pid-file
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-02; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
PIDF="$PGDATA/postmaster.pid"
ALREADY=0
if [[ -f "$PIDF" ]] && ! pg_up; then
  OP=$(head -1 "$PIDF" 2>/dev/null)
  if [[ "$OP" =~ ^[0-9]+$ ]] && [[ "$(ps -p "$OP" -o comm= 2>/dev/null)" == "sleep" ]]; then ALREADY=1; fi
fi
if [[ $ALREADY -eq 0 ]]; then
  # 1. stop cleanly, 2. hold a PID with a harmless sleep, 3. leave a postmaster.pid pointing at it
  systemctl stop postgresql-16 >/dev/null 2>&1
  for _ in $(seq 1 20); do pg_up || break; sleep 1; done
  rm -f "$PIDF"
  # the decoy must be owned by postgres: PostgreSQL 16 treats a pid it cannot signal (EPERM)
  # with a free shared-memory key as a stale lock and starts anyway
  sudo -u postgres setsid nohup sleep 86400 >/dev/null 2>&1 &
  sleep 1
  SP=$(pgrep -n -x sleep -u postgres)
  echo "$SP" > "$STATE_DIR/stale_pid"
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$SP" "$PGDATA" "$(date +%s)" "$PGPORT" "/run/postgresql" "*" "  0         0" > "$PIDF"
  chown postgres:postgres "$PIDF"; chmod 600 "$PIDF"
fi
systemctl start postgresql-16 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL failed to start. Service is DOWN."
say "Error in logs mentions lock file / postmaster.pid."
exit 0
