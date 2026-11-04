#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/08-full-table-lock
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
STATE_DIR=/var/lib/suta-survive/module05-08; mkdir -p "$STATE_DIR"

[[ -x "$PGBIN/postgres" ]] || { say "postgresql-16 is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
DB=stepup_store
APP=bad_migration_script
if [[ "$(psq "$DB" "SELECT count(*) FROM pg_stat_activity WHERE application_name = '$APP'")" == "0" ]]; then
psq "$DB" "CREATE TABLE IF NOT EXISTS products (product_id serial PRIMARY KEY, name text NOT NULL, price numeric(10,2), stock int)" >/dev/null
psq "$DB" "INSERT INTO products (name, price, stock) SELECT * FROM (VALUES ('Widget A', 19.99, 150), ('Widget B', 29.99, 80), ('Gadget C', 49.99, 200), ('Gadget D', 99.99, 50), ('Thingamajig', 9.99, 500)) v WHERE NOT EXISTS (SELECT 1 FROM products)" >/dev/null
  printf '%s\n' 'BEGIN;' 'LOCK TABLE products IN ACCESS EXCLUSIVE MODE;' 'SELECT pg_sleep(3600);' > "$STATE_DIR/lock.sql"
  chmod 644 "$STATE_DIR/lock.sql"
  nohup sudo -u postgres env PGAPPNAME="$APP" "$PGBIN/psql" -p "$PGPORT" -d "$DB" -X -tAq -f "$STATE_DIR/lock.sql" >/dev/null 2>&1 &
  echo "$!" > "$STATE_DIR/holder.pid"
  sleep 2
  nohup sudo -u postgres env PGAPPNAME=storefront "$PGBIN/psql" -p "$PGPORT" -d "$DB" -X -tAq -c "SELECT * FROM products WHERE product_id = 1" >/dev/null 2>&1 &
  echo "$!" > "$STATE_DIR/reader.pid"
  sleep 1
fi
say "sessions waiting on a lock: $(psq "$DB" "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock'")"
say ""
say 'ALERT: Products table is completely inaccessible.'
say 'All queries against the products table are hanging.'
say 'The storefront is down - customers cannot view or purchase products.'
say 'A migration script appears to be holding a lock.'
exit 0
