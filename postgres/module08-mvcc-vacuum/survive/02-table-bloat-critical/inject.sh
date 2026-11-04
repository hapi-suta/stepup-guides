#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/02-table-bloat-critical
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-02; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. seed + break: 200k rows, delete 80% with autovacuum disabled on the table (idempotent)
psq stepup_store "CREATE TABLE IF NOT EXISTS critical_bloat (id int PRIMARY KEY, payload text)"
psq stepup_store "ALTER TABLE critical_bloat SET (autovacuum_enabled = false)"
dead=$(psq stepup_store "SELECT COALESCE(max(n_dead_tup),0) FROM pg_stat_user_tables WHERE relname='critical_bloat'")
if [[ "${dead:-0}" -lt 50000 ]]; then
  psq stepup_store "TRUNCATE critical_bloat"
  psq stepup_store "INSERT INTO critical_bloat SELECT g, 'bloat row ' || g FROM generate_series(1,200000) g"
  psq stepup_store "DELETE FROM critical_bloat WHERE id % 5 <> 0"
fi
sleep 2
say "critical_bloat is far larger on disk than its row count suggests."
say ""
say "ALERT: Table 'critical_bloat' has approximately 80% dead tuples."
say "The Pulse dashboard shows critical dead ratio."
say "Disk usage is growing. Investigate and remediate."
exit 0
