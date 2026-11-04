#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/02-shared-buffers-too-high
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
STATE_DIR=/var/lib/suta-survive/module04-02; mkdir -p "$STATE_DIR"

AUTO="$PGDATA/postgresql.auto.conf"
[[ -x "$PGBIN/postgres" && -f "$AUTO" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! grep -qF "shared_buffers = '64GB'" "$AUTO"; then
  if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
  cp -p "$AUTO" "$STATE_DIR/postgresql.auto.conf.before"
  psq postgres "SHOW shared_buffers" > "$STATE_DIR/shared_buffers.before" 2>/dev/null
  sed -i '/^shared_buffers[[:space:]]*=/d' "$AUTO"
  [[ -n "$(tail -c1 "$AUTO")" ]] && echo >> "$AUTO"
  printf "shared_buffers = '64GB'\n" >> "$AUTO"
fi
systemctl restart postgresql-16 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say 'ALERT: PostgreSQL failed to start. Service is DOWN.'
say 'A DBA ran ALTER SYSTEM to increase shared_buffers for'
say 'better cache performance. Now PG will not start.'
exit 0
