#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/05-vacuum-full-locks
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL is not running and could not be started"; exit 1; }; }

vf_pid() { psq postgres "SELECT pid FROM pg_stat_activity WHERE query = 'VACUUM FULL vfull_lockout' AND pid <> pg_backend_pid() LIMIT 1"; }
if [[ -z "$(vf_pid)" ]]; then
  # 1. seed: 25000 rows, half deleted; an expression index whose function is slow only when suta.slow=on,
  #    so the VACUUM FULL index rebuild runs for minutes while normal sessions are unaffected
  psq stepup_store "CREATE OR REPLACE FUNCTION suta_slow_key(i int) RETURNS int LANGUAGE plpgsql IMMUTABLE AS \$f\$ BEGIN IF current_setting('suta.slow', true) = 'on' THEN PERFORM pg_sleep(0.01); END IF; RETURN i; END \$f\$"
  psq stepup_store "CREATE TABLE IF NOT EXISTS vfull_lockout (id int PRIMARY KEY, payload text)"
  if [[ "$(psq stepup_store "SELECT count(*) FROM vfull_lockout")" == "0" ]]; then
    psq stepup_store "INSERT INTO vfull_lockout SELECT g, 'row ' || g FROM generate_series(1,50000) g"
    psq stepup_store "CREATE INDEX IF NOT EXISTS vfull_lockout_slow_idx ON vfull_lockout (suta_slow_key(id))"
    psq stepup_store "DELETE FROM vfull_lockout WHERE id > 25000"
  fi
  # 2. break: VACUUM FULL in the background (holds ACCESS EXCLUSIVE), then a reader that queues behind it
  PGOPTIONS="-c suta.slow=on" nohup setsid sudo -u postgres env PGOPTIONS="-c suta.slow=on" "$PGBIN/psql" -p "$PGPORT" -d stepup_store -tAXqc "VACUUM FULL vfull_lockout" </dev/null >/dev/null 2>&1 &
  for _ in $(seq 1 10); do [[ -n "$(vf_pid)" ]] && break; sleep 1; done
  nohup setsid sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d stepup_store -tAXqc "SELECT count(*) FROM vfull_lockout" </dev/null >/dev/null 2>&1 &
  sleep 2
fi
say "Queries against vfull_lockout are hanging; a VACUUM FULL session is active."
say ""
say "ALERT: VACUUM FULL is running on vfull_lockout."
say "All queries against this table are blocked (lock wait)."
say "Application is reporting query timeouts."
say "You must decide: wait for it to finish, or cancel it."
exit 0
