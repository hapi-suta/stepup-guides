#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/06-runaway-query
# inject.sh - breaks the lab (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module05-06; mkdir -p "$STATE_DIR"

[[ -x "$PGBIN/postgres" ]] || { say "postgresql-16 is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
DB=stepup_store
APP=runaway_report_job; PIDF="$STATE_DIR/job.pid"
psq "$DB" "ALTER DATABASE stepup_store RESET statement_timeout" >/dev/null
if [[ "$(psq "$DB" "SELECT count(*) FROM pg_stat_activity WHERE application_name = '$APP' AND state = 'active'")" == "0" ]]; then
  printf '%s\n' 'SET statement_timeout = 0;' 'SELECT COUNT(*) FROM generate_series(1, 50000) a CROSS JOIN generate_series(1, 50000) b WHERE a > b;' > "$STATE_DIR/job.sql"
  chmod 644 "$STATE_DIR/job.sql"
  nohup sudo -u postgres env PGAPPNAME="$APP" "$PGBIN/psql" -p "$PGPORT" -d "$DB" -X -tAq -f "$STATE_DIR/job.sql" >/dev/null 2>&1 &
  echo "$!" > "$PIDF"
  sleep 3
fi
say "load average: $(cut -d' ' -f1-3 /proc/loadavg)"
say ""
say 'ALERT: Server CPU at 100%. Database response time spiking.'
say 'A nightly report job appears stuck and is consuming all available CPU.'
say 'Other queries are being starved.'
say 'Application name: runaway_report_job'
exit 0
