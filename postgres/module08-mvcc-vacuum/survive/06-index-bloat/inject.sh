#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/06-index-bloat
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-06; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# pgstattuple ships with postgresql16-contrib; the runbook diagnoses with pgstatindex
if ! psq stepup_store "CREATE EXTENSION IF NOT EXISTS pgstattuple" >/dev/null 2>&1; then
  say "PRECONDITION: install postgresql16-contrib (pgstattuple extension) first"; exit 2
fi
dens() { psq stepup_store "SELECT COALESCE(round(avg_leaf_density)::int, 100) FROM pgstatindex('idx_email')" 2>/dev/null; }
d=$(dens)
if [[ -z "$d" || "$d" -gt 40 ]]; then
  # 1. seed: 100k rows with a random-ordered text index, autovacuum off on the table
  psq stepup_store "DROP TABLE IF EXISTS index_bloat_demo"
  psq stepup_store "CREATE TABLE index_bloat_demo (id int PRIMARY KEY, email text)"
  psq stepup_store "ALTER TABLE index_bloat_demo SET (autovacuum_enabled = false)"
  psq stepup_store "INSERT INTO index_bloat_demo SELECT g, md5(g::text) || '@example.com' FROM generate_series(1,100000) g"
  psq stepup_store "CREATE INDEX idx_email ON index_bloat_demo (email)"
  # 2. break: delete 90000 scattered rows, then VACUUM so the index pages stay allocated but nearly empty
  psq stepup_store "DELETE FROM index_bloat_demo WHERE id % 10 <> 0"
  psq stepup_store "VACUUM index_bloat_demo"
  sleep 2
fi
say "Queries on index_bloat_demo.email read far more pages than the row count explains."
say ""
say "ALERT: Index idx_email on index_bloat_demo is bloated."
say "90,000 rows were deleted. The index is still large."
say "Queries on email column are slower than expected."
say "Index needs to be rebuilt."
exit 0
