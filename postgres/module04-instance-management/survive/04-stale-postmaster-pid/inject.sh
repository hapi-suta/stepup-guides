#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/04-stale-postmaster-pid
# inject.sh - breaks the lab (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module04-04; mkdir -p "$STATE_DIR"

PIDFILE="$PGDATA/postmaster.pid"; ENVF=/tmp/chaos-04-state.env
[[ -x "$PGBIN/postgres" && -d "$PGDATA" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
decoy=$(grep '^DECOY_PID=' "$ENVF" 2>/dev/null | cut -d= -f2)
if [[ -n "$decoy" ]] && kill -0 "$decoy" 2>/dev/null && [[ "$(head -1 "$PIDFILE" 2>/dev/null)" == "$decoy" ]]; then
  say "stale lock file already in place"
else
  systemctl stop postgresql-16 >/dev/null 2>&1
  for _ in $(seq 1 20); do [[ -f "$PIDFILE" ]] || break; sleep 1; done
  rm -f "$PIDFILE"
  nohup sudo -u postgres sleep 86400 >/dev/null 2>&1 &
  sleep 1
  decoy=$(pgrep -u postgres -nx sleep)
  [[ -n "$decoy" ]] || { say "could not start decoy"; exit 1; }
  echo "DECOY_PID=$decoy" > "$ENVF"; cp "$ENVF" "$STATE_DIR/state.env"
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$decoy" "$PGDATA" "$(date +%s)" "$PGPORT" "/run/postgresql" "localhost" "  5432001     0" "ready" > "$PIDFILE"
  chown postgres:postgres "$PIDFILE"; chmod 600 "$PIDFILE"
fi
systemctl start postgresql-16 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say 'ALERT: PostgreSQL crashed (server power failure simulated).'
say 'Attempts to start PostgreSQL fail with:'
say ''\''Is another postmaster running on port 5432?'\'''
say 'The database is DOWN.'
exit 0
