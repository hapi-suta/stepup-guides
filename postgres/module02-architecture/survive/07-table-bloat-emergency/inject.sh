#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/07-table-bloat-emergency
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi

DEAD=$(psq labdb "SELECT coalesce((SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='chaos_bloat_test'), 0)")
OPT=$(psq labdb "SELECT coalesce((SELECT reloptions::text FROM pg_class WHERE relname='chaos_bloat_test' AND relkind='r'), '')")
if [[ "${DEAD:-0}" -lt 100000 || "$OPT" != *autovacuum_enabled=false* ]]; then
  # 50000 live rows, autovacuum off, then 3 full-table updates = ~150000 dead tuples
  psq labdb "DROP TABLE IF EXISTS chaos_bloat_test"
  psq labdb "CREATE TABLE chaos_bloat_test (id int PRIMARY KEY, val int, pad text) WITH (autovacuum_enabled = false)"
  psq labdb "INSERT INTO chaos_bloat_test SELECT g, 0, repeat('b', 60) FROM generate_series(1, 50000) g"
  for i in 1 2 3; do psq labdb "UPDATE chaos_bloat_test SET val = val + 1"; done
  sleep 3
fi
say "chaos_bloat_test: $(psq labdb "SELECT n_live_tup || ' live, ' || n_dead_tup || ' dead' FROM pg_stat_user_tables WHERE relname='chaos_bloat_test'")"
say ""
say "ALERT: Table bloat reported on labdb (Severity MEDIUM)."
say "Queries on a single table are slow and its disk usage keeps growing."
exit 0
