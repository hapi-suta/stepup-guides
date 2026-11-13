#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/07-initdb-wrong-locale
# inject.sh - breaks the server (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module03-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }

PG15BIN=/usr/pgsql-15/bin; PG15DATA=/opt/pgsql/data15
if [[ ! -x "$PG15BIN/postgres" || ! -f "$PG15DATA/PG_VERSION" || ! -f /usr/lib/systemd/system/postgresql-15.service ]]; then
  say "PRECONDITION: finish Tutorial 2 (multi-version install: PostgreSQL 15 on port 5433) first"; exit 2
fi
p15() { sudo -u postgres "$PG15BIN/psql" -p 5433 -d postgres -v ON_ERROR_STOP=1 -tAXqc "$1"; }
locale -a 2>/dev/null | grep -qi '^en_US\.utf-\?8$' || { say "PRECONDITION: OS locale en_US.UTF-8 missing (dnf install glibc-langpack-en) - needed so the learner can fix it"; exit 2; }
CUR=$(p15 "SHOW lc_collate" 2>/dev/null)
if [[ "$CUR" != "C" ]]; then
  # 1. set the existing cluster aside, 2. initdb with the C locale, 3. port 5433, 4. start and add the table the runbook sorts
  systemctl stop postgresql-15 >/dev/null 2>&1
  [[ -d "$PG15DATA" ]] && mv "$PG15DATA" "$PG15DATA.suta-orig.$(date +%s)"
  sudo -u postgres "$PG15BIN/initdb" -D "$PG15DATA" --locale=C --encoding=UTF8 >/dev/null 2>&1 || { say "initdb failed"; exit 1; }
  sed -i -E 's/^#?port[[:space:]]*=.*/port = 5433/' "$PG15DATA/postgresql.conf"
  grep -qE '^port = 5433' "$PG15DATA/postgresql.conf" || printf '\nport = 5433\n' >> "$PG15DATA/postgresql.conf"
  systemctl reset-failed postgresql-15 >/dev/null 2>&1
  systemctl start postgresql-15 >/dev/null 2>&1
  for _ in $(seq 1 20); do sudo -u postgres "$PG15BIN/pg_isready" -q -p 5433 && break; sleep 1; done
  p15 "CREATE TABLE IF NOT EXISTS locale_test (name text)" && p15 "INSERT INTO locale_test SELECT unnest(ARRAY['apple','Banana','cherry','eclair','elephant'])"
fi
say "postgresql-15: $(systemctl is-active postgresql-15)"
say ""
say "ALERT: String sorting and text searches behave differently from production."
say "PostgreSQL 15 was reinitialized by a teammate; the instance is running."
exit 0
