#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/09-stale-statistics
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-09; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi

RT=$(psq labdb "SELECT coalesce((SELECT reltuples::bigint FROM pg_class WHERE relname='chaos_stats_test' AND relkind='r'), 0)")
OPT=$(psq labdb "SELECT coalesce((SELECT reloptions::text FROM pg_class WHERE relname='chaos_stats_test' AND relkind='r'), '')")
if [[ "${RT:-0}" -lt 100000 || "$OPT" != *autovacuum_enabled=false* ]]; then
  # 500000 rows analysed, then 499000 deleted with autovacuum (and autoanalyze) off: the planner still believes 500000
  psq labdb "DROP TABLE IF EXISTS chaos_stats_test"
  psq labdb "CREATE TABLE chaos_stats_test (id int, category int, val int) WITH (autovacuum_enabled = false)"
  psq labdb "INSERT INTO chaos_stats_test SELECT g, g % 1000, g FROM generate_series(1, 500000) g"
  psq labdb "CREATE INDEX idx_chaos_stats_category ON chaos_stats_test (category)"
  psq labdb "ANALYZE chaos_stats_test"
  psq labdb "DELETE FROM chaos_stats_test WHERE id > 1000"
  sleep 2
fi
say "chaos_stats_test now holds $(psq labdb "SELECT count(*) FROM chaos_stats_test") rows."
say ""
say "ALERT: Query plans on labdb look wrong (Severity MEDIUM)."
say "A query that should be fast on one table is slow; the planner picks a poor plan."
exit 0
