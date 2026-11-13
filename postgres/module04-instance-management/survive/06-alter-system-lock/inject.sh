#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/06-alter-system-lock
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
STATE_DIR=/var/lib/suta-survive/module04-06; mkdir -p "$STATE_DIR"

CONFD="$PGDATA/conf.d"; CONF="$PGDATA/postgresql.conf"
[[ -x "$PGBIN/postgres" && -f "$CONF" ]] || { say "postgresql-16 is not installed at $PGDATA"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
sudo -u postgres mkdir -p "$CONFD"
grep -qE "^[[:space:]]*include_dir[[:space:]]*=[[:space:]]*'conf.d'" "$CONF" || printf "\ninclude_dir = 'conf.d'\n" >> "$CONF"
[[ -f "$CONFD/tuning.conf" && ! -f "$STATE_DIR/tuning.conf.before" ]] && cp -p "$CONFD/tuning.conf" "$STATE_DIR/tuning.conf.before"
cat > "$CONFD/tuning.conf" <<'CFG'
# Tuning parameters - set by DBA team
shared_buffers = '256MB'
work_mem = '16MB'
maintenance_work_mem = '128MB'
effective_cache_size = '768MB'
CFG
chown postgres:postgres "$CONFD/tuning.conf"; chmod 600 "$CONFD/tuning.conf"
psq postgres "ALTER SYSTEM SET shared_buffers = '32MB'" >/dev/null
psq postgres "ALTER SYSTEM SET log_min_duration_statement = 0" >/dev/null
psq postgres "ALTER SYSTEM SET work_mem = '1MB'" >/dev/null
systemctl restart postgresql-16 >/dev/null 2>&1
wait_up || { say "PostgreSQL would not restart"; exit 1; }
say "shared_buffers now: $(psq postgres 'SHOW shared_buffers')"
say ""
say 'ALERT: PostgreSQL is running but performance is degraded.'
say 'The DBA team set tuning values in conf.d/tuning.conf but'
say 'shared_buffers shows 32MB instead of 256MB, and work_mem'
say 'shows 1MB instead of 16MB. Every query is being logged.'
say 'Something is overriding the conf.d settings.'
exit 0
