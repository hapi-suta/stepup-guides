#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/09-conflicting-confd-override
# inject.sh - breaks the lab (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module04-09; mkdir -p "$STATE_DIR"

CONFD="$PGDATA/conf.d"; CONF="$PGDATA/postgresql.conf"; OVR="$CONFD/zzz-override.conf"
[[ -x "$PGBIN/postgres" && -f "$CONF" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if [[ ! -f "$OVR" ]]; then
  if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
  sudo -u postgres mkdir -p "$CONFD"
  grep -qE "^[[:space:]]*include_dir[[:space:]]*=[[:space:]]*'conf.d'" "$CONF" || { cp -p "$CONF" "$STATE_DIR/postgresql.conf.before"; printf "\ninclude_dir = 'conf.d'\n" >> "$CONF"; }
  printf '%s\n' '# Emergency maintenance override - DO NOT DELETE' '# Added by ops team for load balancer testing' 'port = 5499' > "$OVR"
  chown postgres:postgres "$OVR"; chmod 600 "$OVR"
  systemctl restart postgresql-16 >/dev/null 2>&1
fi
for _ in $(seq 1 20); do sudo -u postgres "$PGBIN/pg_isready" -q -p 5499 && break; sleep 1; done
say "pg_isready -p 5432: $(sudo -u postgres "$PGBIN/pg_isready" -p 5432)"
say ""
say 'ALERT: Application connections are failing.'
say 'All services connecting to PostgreSQL on port 5432 report'
say ''\''connection refused'\''. The database process appears to be'
say 'running but something changed the port.'
exit 0
