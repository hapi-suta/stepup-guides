#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/07-toast-table-bloat
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

dead=$(psq stepup_store "SELECT COALESCE(max(n_dead_tup),0) FROM pg_stat_user_tables WHERE relname='toast_bloat_demo'" 2>/dev/null)
if [[ "${dead:-0}" -lt 1000 ]]; then
  # 1. seed: 2000 rows of ~16 KB incompressible text stored out of line, autovacuum off for table and TOAST
  psq stepup_store "DROP TABLE IF EXISTS toast_bloat_demo"
  psq stepup_store "CREATE TABLE toast_bloat_demo (id int PRIMARY KEY, body text)"
  psq stepup_store "ALTER TABLE toast_bloat_demo ALTER COLUMN body SET STORAGE EXTERNAL"
  psq stepup_store "ALTER TABLE toast_bloat_demo SET (autovacuum_enabled = false, toast.autovacuum_enabled = false)"
  psq stepup_store "INSERT INTO toast_bloat_demo SELECT g, (SELECT string_agg(md5(random()::text || g || k), '') FROM generate_series(1,500) k) FROM generate_series(1,2000) g"
  # 2. break: two rounds of large-text updates rewrite every TOAST chunk twice
  psq stepup_store "UPDATE toast_bloat_demo SET body = body || 'a'"
  psq stepup_store "UPDATE toast_bloat_demo SET body = body || 'b'"
  sleep 2
fi
say "Disk usage keeps growing but toast_bloat_demo only holds 2000 rows."
say ""
say "ALERT: Table toast_bloat_demo has excessive TOAST storage."
say "Repeated large text updates have bloated the TOAST table."
say "Disk usage on the data tablespace is growing unexpectedly."
exit 0
