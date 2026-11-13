#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/02-table-bloat
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
STATE_DIR=/var/lib/suta-survive/module05-02; mkdir -p "$STATE_DIR"

[[ -x "$PGBIN/postgres" ]] || { say "postgresql-16 is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
DB=stepup_store
cur=$(psq "$DB" "SELECT (c.reloptions @> ARRAY['autovacuum_enabled=false'])::int::text || coalesce((SELECT (s.n_dead_tup >= 100000)::int::text FROM pg_stat_user_tables s WHERE s.relid = c.oid), '0') FROM pg_class c WHERE c.relname = 'bloat_demo' AND c.relkind = 'r'" 2>/dev/null)
if [[ "$cur" != "11" ]]; then
  psq "$DB" 'DROP TABLE IF EXISTS bloat_demo' >/dev/null
  psq "$DB" 'CREATE TABLE bloat_demo (id int PRIMARY KEY, payload text, counter int) WITH (autovacuum_enabled = false)' >/dev/null
  psq "$DB" "INSERT INTO bloat_demo SELECT g, repeat('data', 20), 0 FROM generate_series(1, 10000) g" >/dev/null
  upd=""; for _ in $(seq 1 20); do upd+="UPDATE bloat_demo SET counter = counter + 1;"; done
  psq "$DB" "$upd" >/dev/null
  sleep 2
fi
say "bloat_demo created with autovacuum disabled"
say ""
say 'ALERT: The bloat_demo table has accumulated dead tuples.'
say 'Table size is growing but row count is not. Queries are'
say 'slower because PostgreSQL must skip over dead rows.'
say 'Autovacuum has not cleaned this table.'
exit 0
