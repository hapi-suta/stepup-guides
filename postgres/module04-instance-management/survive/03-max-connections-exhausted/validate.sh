#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/03-max-connections-exhausted
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
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
STATE_DIR=/var/lib/suta-survive/module04-03; mkdir -p "$STATE_DIR"

AUTO="$PGDATA/postgresql.auto.conf"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "PostgreSQL accepts connections" "1" "$(psq postgres 'SELECT 1' 2>/dev/null)"
mc=$(psq postgres "SHOW max_connections" 2>/dev/null)
if [[ "$mc" =~ ^[0-9]+$ && "$mc" -ge 50 ]]; then ok "max_connections is not 5 ($mc)"; else bad "max_connections is not 5 (expected >= 50, got ${mc:-<none>})"; fi
sr=$(psq postgres "SHOW superuser_reserved_connections" 2>/dev/null)
if [[ "$sr" =~ ^[0-9]+$ && "$sr" -ge 3 ]]; then ok "superuser_reserved_connections is at least 3 ($sr)"; else bad "superuser_reserved_connections is at least 3 (got ${sr:-<none>})"; fi
if pgrep -f 'pg_sleep\(86400\)' >/dev/null; then bad "no sleeping chaos backends remain"; else ok "no sleeping chaos backends remain"; fi
if grep -qE "^max_connections[[:space:]]*=[[:space:]]*'?5'?[[:space:]]*$" "$AUTO"; then bad "postgresql.auto.conf has no max_connections = 5"; else ok "postgresql.auto.conf has no max_connections = 5"; fi
finish
