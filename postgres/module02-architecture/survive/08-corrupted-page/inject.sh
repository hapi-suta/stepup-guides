#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/08-corrupted-page
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi

if ! psq labdb "SELECT count(*) FROM chaos_corrupt_test" 2>&1 | grep -q 'invalid page'; then
  # 1. 1000-row table flushed to disk, 2. clean stop (empties shared buffers), 3. zero the 24-byte header of page 0, 4. start
  psq labdb "DROP TABLE IF EXISTS chaos_corrupt_test"
  psq labdb "CREATE TABLE chaos_corrupt_test (id int, payload text)"
  psq labdb "INSERT INTO chaos_corrupt_test SELECT g, md5(g::text) || md5((g * 3)::text) FROM generate_series(1, 1000) g"
  psq labdb "CHECKPOINT"
  REL=$(psq labdb "SELECT pg_relation_filepath('chaos_corrupt_test')")
  echo "$REL" > "$STATE_DIR/relfilepath"
  systemctl stop postgresql-16 >/dev/null 2>&1
  for _ in $(seq 1 20); do pg_up || break; sleep 1; done
  dd if=/dev/zero of="$PGDATA/$REL" bs=1 count=24 conv=notrunc 2>/dev/null
  systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not restart"; exit 1; }
fi
say "PostgreSQL is up."
say ""
say "ALERT: Database error reported on labdb (Severity HIGH)."
say "One table is unreadable; the rest of the database is intact."
exit 0
