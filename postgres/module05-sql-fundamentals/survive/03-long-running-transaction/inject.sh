#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/03-long-running-transaction
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
STATE_DIR=/var/lib/suta-survive/module05-03; mkdir -p "$STATE_DIR"

[[ -x "$PGBIN/postgres" ]] || { say "postgresql-16 is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
DB=stepup_store
APP=chaos-03-idle; PIDF="$STATE_DIR/holder.pid"
psq "$DB" "CREATE TABLE IF NOT EXISTS orders (order_id serial PRIMARY KEY, customer_id int, status text, amount numeric(10,2), created_at timestamptz DEFAULT now())" >/dev/null
psq "$DB" "INSERT INTO orders (customer_id, status, amount) SELECT 1, 'new', 9.99 WHERE NOT EXISTS (SELECT 1 FROM orders)" >/dev/null
psq "$DB" "ALTER SYSTEM RESET idle_in_transaction_session_timeout" >/dev/null
psq "$DB" "SELECT pg_reload_conf()" >/dev/null
if [[ "$(psq "$DB" "SELECT count(*) FROM pg_stat_activity WHERE application_name = '$APP'")" == "0" ]]; then
  printf '%s\n' 'BEGIN ISOLATION LEVEL REPEATABLE READ;' 'SELECT * FROM orders LIMIT 1;' '\watch 5' > "$STATE_DIR/hold.sql"
  chmod 644 "$STATE_DIR/hold.sql"
  nohup sudo -u postgres env PGAPPNAME="$APP" "$PGBIN/psql" -p "$PGPORT" -d "$DB" -X -tAq -f "$STATE_DIR/hold.sql" >/dev/null 2>&1 &
  echo "$!" > "$PIDF"
  sleep 3
fi
say "sessions in idle in transaction: $(psq "$DB" "SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction'")"
say ""
say 'ALERT: A session is stuck in '\''idle in transaction'\'' state.'
say 'This session has been open for over 2 hours and is blocking'
say 'autovacuum and preventing VACUUM FULL from running on the orders table.'
exit 0
