#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/10-pg-hba-blocks-connections
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
STATE_DIR=/var/lib/suta-survive/module04-10; mkdir -p "$STATE_DIR"

HBA="$PGDATA/pg_hba.conf"
[[ -x "$PGBIN/postgres" && -f "$HBA" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! grep -qE '^local[[:space:]]+all[[:space:]]+all[[:space:]]+reject' "$HBA"; then
  if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
  cp -p "$HBA" "$STATE_DIR/pg_hba.conf.before"
  awk '!d && $0 !~ /^[[:space:]]*(#|$)/ {print "# chaos injection - reject all local connections"; print "local   all   all   reject"; print ""; print "# original rules below"; d=1} {print}' "$STATE_DIR/pg_hba.conf.before" > "$STATE_DIR/pg_hba.conf.new"
  cat "$STATE_DIR/pg_hba.conf.new" > "$HBA"
  sudo -u postgres "$PGBIN/pg_ctl" -D "$PGDATA" reload >/dev/null 2>&1
  sleep 1
fi
say "pg_isready: $(sudo -u postgres "$PGBIN/pg_isready" -p "$PGPORT")"
say ""
say 'ALERT: PostgreSQL is running but all connections fail.'
say 'Users report: FATAL: pg_hba.conf rejects connection'
say 'The security team updated authentication rules and now'
say 'nobody can connect to the database.'
exit 0
