#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/10-bgwriter-disabled
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module02-10; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi

BG=$(psq postgres "SELECT setting FROM pg_settings WHERE name='bgwriter_lru_maxpages'")
CT=$(psq postgres "SELECT setting FROM pg_settings WHERE name='checkpoint_timeout'")
if [[ "$BG" != "0" || "$CT" != "1800" ]]; then
  printf 'bgwriter_lru_maxpages=%s\ncheckpoint_timeout=%s\n' "$BG" "$CT" > "$STATE_DIR/before"
  psq postgres "ALTER SYSTEM SET bgwriter_lru_maxpages = 0"
  psq postgres "ALTER SYSTEM SET checkpoint_timeout = '30min'"
  psq postgres "SELECT pg_reload_conf()" >/dev/null
  sleep 2
fi
say "PostgreSQL is up."
say ""
say "ALERT: Latency increased on all queries (Severity MEDIUM)."
say "I/O wait is rising and backends are spending time writing buffers themselves."
exit 0
