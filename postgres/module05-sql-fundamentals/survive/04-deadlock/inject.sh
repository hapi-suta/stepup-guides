#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/04-deadlock
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
STATE_DIR=/var/lib/suta-survive/module05-04; mkdir -p "$STATE_DIR"

[[ -x "$PGBIN/postgres" ]] || { say "postgresql-16 is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
DB=stepup_store
psq "$DB" 'CREATE TABLE IF NOT EXISTS deadlock_accounts (id int PRIMARY KEY, name text NOT NULL, balance numeric(10,2) NOT NULL)' >/dev/null
reset_bal() { psq "$DB" "INSERT INTO deadlock_accounts VALUES (1, 'Account A', 1000.00), (2, 'Account B', 2000.00) ON CONFLICT (id) DO UPDATE SET balance = EXCLUDED.balance, name = EXCLUDED.name" >/dev/null; }
reset_bal
tx() { psq "$DB" "UPDATE deadlock_accounts SET balance = balance - 100 WHERE id = $1; SELECT pg_sleep(2); UPDATE deadlock_accounts SET balance = balance + 100 WHERE id = $2;" >/dev/null 2>&1; }
tx 1 2 &
tx 2 1 &
wait
reset_bal
say "transfer jobs finished; deadlock_accounts rows: $(psq "$DB" 'SELECT count(*) FROM deadlock_accounts')"
say ""
say 'ALERT: A deadlock was detected and logged.'
say 'Two application threads are failing with '\''deadlock detected'\'' errors'
say 'when processing concurrent transfers between accounts.'
say 'The operations are being retried but keep deadlocking.'
exit 0
