#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/01-shared-buffers-too-low
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-01
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

CONF="$PGDATA/postgresql.conf"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
sb=$(psq stepup_store "select setting::bigint*8192 from pg_settings where name='shared_buffers'" 2>/dev/null)
if [[ -n "$sb" && "$sb" -ge 67108864 ]]; then ok "shared_buffers is at least 64MB ($((sb/1048576))MB)"; else bad "shared_buffers is at least 64MB (got ${sb:-<none>} bytes)"; fi
if grep -q '# chaos injection' "$CONF"; then bad "chaos injection comment removed from postgresql.conf"; else ok "chaos injection comment removed from postgresql.conf"; fi
q=$(psq stepup_store "select count(*) from pg_class" 2>/dev/null)
if [[ -n "$q" ]]; then ok "query against stepup_store works"; else bad "query against stepup_store works"; fi
finish
