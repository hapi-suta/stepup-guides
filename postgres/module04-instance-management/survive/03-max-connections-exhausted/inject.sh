#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/03-max-connections-exhausted
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
STATE_DIR=/var/lib/suta-survive/module04-03; mkdir -p "$STATE_DIR"

AUTO="$PGDATA/postgresql.auto.conf"
[[ -x "$PGBIN/postgres" && -f "$AUTO" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
PIDS="$STATE_DIR/sleeper.pids"; touch "$PIDS"
alive() { local n=0 p; while read -r p; do [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null && n=$((n+1)); done < "$PIDS"; echo "$n"; }
if ! grep -qF "max_connections = '5'" "$AUTO"; then
  if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
  cp -p "$AUTO" "$STATE_DIR/postgresql.auto.conf.before"
  sed -i '/^max_connections[[:space:]]*=/d; /^superuser_reserved_connections[[:space:]]*=/d' "$AUTO"
  [[ -n "$(tail -c1 "$AUTO")" ]] && echo >> "$AUTO"
  printf "max_connections = '5'\nsuperuser_reserved_connections = '0'\n" >> "$AUTO"
  systemctl restart postgresql-16 >/dev/null 2>&1
fi
wait_up || { say "PostgreSQL would not start"; exit 1; }
need=$((5 - $(alive)))
for _ in $(seq 1 "$need"); do
  nohup sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d labdb -tAXqc "SET client_connection_check_interval = '1s'; SELECT pg_sleep(86400)" >/dev/null 2>&1 &
  echo "$!" >> "$PIDS"
  sleep 1
done
sleep 1
say "pg_isready: $(sudo -u postgres "$PGBIN/pg_isready" -p "$PGPORT")"
say ""
say 'ALERT: Cannot connect to PostgreSQL.'
say 'All connection slots are in use.'
say 'Application servers report: FATAL: too many clients already'
say 'No new connections can be established.'
exit 0
