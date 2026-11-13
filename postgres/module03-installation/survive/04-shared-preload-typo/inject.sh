#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/04-shared-preload-typo
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module03-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

[[ -x "$PGBIN/postgres" && -f "$PGDATA/postgresql.conf" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
CONF="$PGDATA/postgresql.conf"
if [[ ! -f /usr/pgsql-16/lib/pg_stat_statements.so ]]; then
  say "PRECONDITION: finish Tutorial 4 (extensions: it installs postgresql16-contrib) first"; exit 2
fi
if ! grep -qE "^[[:space:]]*shared_preload_libraries.*pg_stat_statments" "$CONF"; then
  if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
  psq labdb "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" >/dev/null 2>&1
  cp -p "$CONF" "$STATE_DIR/postgresql.conf.before"
  if grep -qE "^[[:space:]]*shared_preload_libraries[[:space:]]*=" "$CONF"; then
    # one active line: misspell the library inside it, or replace its value if the library was not listed
    if grep -E "^[[:space:]]*shared_preload_libraries" "$CONF" | grep -q pg_stat_statements; then
      sed -i -E "/^[[:space:]]*shared_preload_libraries/ s/pg_stat_statements/pg_stat_statments/" "$CONF"
    else
      sed -i -E "s/^[[:space:]]*shared_preload_libraries[[:space:]]*=.*/shared_preload_libraries = 'pg_stat_statments'/" "$CONF"
    fi
  else
    printf "\nshared_preload_libraries = 'pg_stat_statments'\n" >> "$CONF"
  fi
fi
systemctl restart postgresql-16 >/dev/null 2>&1 || true
sleep 2
systemctl reset-failed postgresql-16 >/dev/null 2>&1 || true
say "systemctl status postgresql-16: $(systemctl is-active postgresql-16)"
say ""
say "ALERT: PostgreSQL failed to start. Service is DOWN."
say "A junior DBA modified postgresql.conf to enable query statistics tracking."
say "PG will not start now."
exit 0
