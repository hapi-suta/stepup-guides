#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/03-shared-buffers-too-low
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi

SB=$(psq postgres "SELECT setting::int FROM pg_settings WHERE name='shared_buffers'")
if [[ "$SB" -gt 1024 ]]; then
  # 1. workload table the runbook queries, 2. tiny shared_buffers, 3. restart so it takes effect
  psq labdb "CREATE TABLE IF NOT EXISTS chaos_workload AS SELECT g AS id, repeat('x', 40) || md5(g::text) AS payload FROM generate_series(1, 200000) g"
  echo "$SB" > "$STATE_DIR/shared_buffers_blocks_before"
  psq postgres "ALTER SYSTEM SET shared_buffers = '1MB'"
  systemctl restart postgresql-16 >/dev/null 2>&1
  if ! wait_up; then
    # this build refuses 1MB: fall back to 4MB, still far below what the server needs
    printf "shared_buffers = '4MB'\n" >> "$PGDATA/postgresql.auto.conf"
    systemctl reset-failed postgresql-16 >/dev/null 2>&1
    systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }
  fi
  # cold-cache reads so pg_stat_database shows a poor hit ratio
  psq labdb "SELECT pg_stat_reset()" >/dev/null 2>&1
  psq labdb "SELECT count(*) FROM chaos_workload" >/dev/null 2>&1
  psq labdb "SELECT count(*) FROM chaos_workload WHERE payload LIKE '%zz%'" >/dev/null 2>&1
fi
say "PostgreSQL is up."
say ""
say "ALERT: Database performance severely degraded."
say "Cache hit ratio dropped below expected levels."
say "Applications reporting slow queries."
exit 0
