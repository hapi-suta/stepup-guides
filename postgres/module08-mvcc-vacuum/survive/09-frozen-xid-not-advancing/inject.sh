#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/09-frozen-xid-not-advancing
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-09; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

age=$(psq stepup_store "SELECT age(relfrozenxid) FROM pg_class WHERE relname='xid_freeze_demo'" 2>/dev/null)
opts=$(psq stepup_store "SELECT COALESCE(reloptions::text,'') FROM pg_class WHERE relname='xid_freeze_demo'" 2>/dev/null)
if [[ -z "$age" || "$age" -lt 3000 || "$opts" != *autovacuum_enabled=false* ]]; then
  # 1. seed: 10000 rows, half deleted, autovacuum disabled on the table
  psq stepup_store "DROP TABLE IF EXISTS xid_freeze_demo"
  psq stepup_store "CREATE TABLE xid_freeze_demo (id int PRIMARY KEY, payload text)"
  psq stepup_store "ALTER TABLE xid_freeze_demo SET (autovacuum_enabled = false)"
  psq stepup_store "INSERT INTO xid_freeze_demo SELECT g, 'row ' || g FROM generate_series(1,10000) g"
  psq stepup_store "DELETE FROM xid_freeze_demo WHERE id % 2 = 0"
  # 2. break: age the table by burning ~5000 transaction ids (subtransactions in one session)
  psq stepup_store "CREATE TEMP TABLE burn (i int); DO \$\$ BEGIN FOR i IN 1..5000 LOOP BEGIN INSERT INTO burn VALUES (i); EXCEPTION WHEN others THEN NULL; END; END LOOP; END \$\$;"
  sleep 2
fi
say "xid_freeze_demo shows a much older relfrozenxid than the other tables."
say ""
say "ALERT: Table xid_freeze_demo has autovacuum disabled."
say "relfrozenxid age is growing and frozen XIDs are not advancing."
say "Risk of XID wraparound if left unchecked."
exit 0
