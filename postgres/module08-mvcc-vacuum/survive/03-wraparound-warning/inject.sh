#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/03-wraparound-warning
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

# 1. seed: freeze_needed with autovacuum off (anti-wraparound still ignores that, we stay below its threshold)
psq stepup_store "CREATE TABLE IF NOT EXISTS freeze_needed (id int PRIMARY KEY, payload text)"
psq stepup_store "ALTER TABLE freeze_needed SET (autovacuum_enabled = false)"
[[ "$(psq stepup_store "SELECT count(*) FROM freeze_needed")" == "0" ]] && psq stepup_store "INSERT INTO freeze_needed SELECT g, 'row ' || g FROM generate_series(1,1000) g"
# 2. break: lower the freeze thresholds (100000 is the PostgreSQL minimum; postmaster setting, so restart)
if ! grep -q 'autovacuum_freeze_max_age' "$PGDATA/postgresql.auto.conf"; then
  psq stepup_store "ALTER SYSTEM SET autovacuum_freeze_max_age = 100000"
  psq stepup_store "ALTER SYSTEM SET vacuum_freeze_min_age = 100"
  systemctl restart postgresql-16 >/dev/null 2>&1
  wait_up || { say "PostgreSQL did not come back after restart"; exit 1; }
fi
# 3. age the table: burn about 60k transaction ids with subtransactions (keeps age under the 100000 trigger)
age=$(psq stepup_store "SELECT age(relfrozenxid) FROM pg_class WHERE relname='freeze_needed'")
dbage=$(psq stepup_store "SELECT age(datfrozenxid) FROM pg_database WHERE datname='stepup_store'")
if [[ "${age:-0}" -lt 10000 ]]; then
  burn=$(( 85000 - ${dbage:-0} )); [[ $burn -gt 60000 ]] && burn=60000; [[ $burn -lt 15000 ]] && burn=15000
  psq stepup_store "CREATE TEMP TABLE burn (i int); DO \$\$ BEGIN FOR i IN 1..$burn LOOP BEGIN INSERT INTO burn VALUES (i); EXCEPTION WHEN others THEN NULL; END; END LOOP; END \$\$;"
fi
say "Pulse shows the wraparound risk gauge well above normal for stepup_store."
say ""
say "ALERT: XID age is approaching the freeze threshold."
say "The Pulse dashboard shows high wraparound risk percentage."
say "autovacuum_freeze_max_age has been changed."
say "You must run VACUUM FREEZE to advance relfrozenxid."
exit 0
