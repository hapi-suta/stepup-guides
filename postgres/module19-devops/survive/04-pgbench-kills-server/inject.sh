#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/04-pgbench-kills-server
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module19-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
DB=bench_chaos
pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up; }
pg_up || { say "PostgreSQL is not running"; exit 1; }
[[ -x "$PGBIN/pgbench" ]] || { say "pgbench is not installed (postgresql16-contrib)"; exit 1; }
mc=$(psq postgres "show max_connections")
if [[ "$mc" -gt 20 ]] || ! pgrep -x pgbench >/dev/null; then
  [[ -f "$STATE_DIR/max_connections.before" ]] || say "$mc" >"$STATE_DIR/max_connections.before"
  pkill -TERM -x pgbench 2>/dev/null; sleep 1
  [[ "$(psq postgres "select count(*) from pg_database where datname='$DB'")" == "1" ]] || sudo -u postgres "$PGBIN/createdb" -p "$PGPORT" "$DB"
  sudo -u postgres "$PGBIN/pgbench" -p "$PGPORT" -i -s 1 -q "$DB" >/dev/null 2>&1
  if [[ "$mc" -ne 20 ]]; then
    psq postgres "ALTER SYSTEM SET max_connections = 20" >/dev/null
    systemctl restart postgresql-16 >/dev/null 2>&1; wait_up
  fi
  for c in 17 15 12 8; do
    others=$(psq postgres "select count(*) from pg_stat_activity where backend_type='client backend' and pid<>pg_backend_pid()")
    n=$(( c - others )); (( n < 1 )) && n=1
    nohup setsid sudo -u postgres "$PGBIN/pgbench" -p "$PGPORT" -c "$n" -j 1 -T 1800 "$DB" >/dev/null 2>&1 </dev/null &
    sleep 4
    pgrep -x pgbench >/dev/null && break
  done
fi
say "pgbench processes: $(pgrep -xc pgbench)"
say "connections: $(psq postgres "select count(*) from pg_stat_activity where backend_type='client backend'") of $(psq postgres 'show max_connections')"
say ""
say "ALERT: Applications report \"FATAL: too many connections for role\" and \"FATAL: sorry, too many clients already.\""
say "A load test is running with more clients than max_connections allows."
exit 0
