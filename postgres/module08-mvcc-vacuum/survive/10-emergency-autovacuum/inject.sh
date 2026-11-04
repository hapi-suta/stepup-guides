#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/10-emergency-autovacuum
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-10; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. seed
psq stepup_store "CREATE TABLE IF NOT EXISTS emergency_vac_demo (id int PRIMARY KEY, payload text)"
[[ "$(psq stepup_store "SELECT count(*) FROM emergency_vac_demo")" == "0" ]] && psq stepup_store "INSERT INTO emergency_vac_demo SELECT g, 'row ' || g FROM generate_series(1,50000) g"
psq stepup_store "ALTER TABLE emergency_vac_demo SET (autovacuum_enabled = false)"
# 2. break: freeze thresholds far below defaults (autovacuum_freeze_max_age is postmaster-level: restart)
if ! grep -q 'autovacuum_freeze_max_age' "$PGDATA/postgresql.auto.conf"; then
  psq stepup_store "ALTER SYSTEM SET autovacuum_freeze_max_age = 100000"
  psq stepup_store "ALTER SYSTEM SET vacuum_freeze_table_age = 50000"
  psq stepup_store "ALTER SYSTEM SET vacuum_freeze_min_age = 1000"
  systemctl restart postgresql-16 >/dev/null 2>&1
  wait_up || { say "PostgreSQL did not come back after restart"; exit 1; }
fi
# 3. push table age past the new 100000 trigger so anti-wraparound autovacuum fires (about 120k xids)
age=$(psq stepup_store "SELECT age(relfrozenxid) FROM pg_class WHERE relname='emergency_vac_demo'")
if [[ "${age:-0}" -lt 100000 ]]; then
  psq stepup_store "CREATE TEMP TABLE burn (i int); DO \$\$ BEGIN FOR i IN 1..120000 LOOP BEGIN INSERT INTO burn VALUES (i); EXCEPTION WHEN others THEN NULL; END; END LOOP; END \$\$;"
  sleep 3
fi
psq postgres "SELECT pid, left(query, 70) FROM pg_stat_activity WHERE query LIKE 'autovacuum:%'" 2>/dev/null
say "Autovacuum workers are running on tables nobody vacuumed manually."
say ""
say "ALERT: Emergency (anti-wraparound) autovacuum is active."
say "autovacuum_freeze_max_age is set to 100000 (default: 200 million)."
say "Anti-wraparound autovacuum cannot be cancelled and ignores I/O throttling."
say "Performance degradation reported on affected tables."
exit 0
