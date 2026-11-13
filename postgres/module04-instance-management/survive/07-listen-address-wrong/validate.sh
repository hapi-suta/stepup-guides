#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/07-listen-address-wrong
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
STATE_DIR=/var/lib/suta-survive/module04-07; mkdir -p "$STATE_DIR"

AUTO="$PGDATA/postgresql.auto.conf"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections on port 5432"; else bad "PostgreSQL accepts connections on port 5432"; fi
la=$(psq postgres 'SHOW listen_addresses' 2>/dev/null)
if [[ -n "$la" && "$la" != "10.0.0.99" ]]; then ok "listen_addresses is not 10.0.0.99 ($la)"; else bad "listen_addresses is not 10.0.0.99 (got ${la:-<none>})"; fi
if grep -qE '^listen_addresses[[:space:]]*=' "$AUTO"; then bad "postgresql.auto.conf has no listen_addresses override"; else ok "postgresql.auto.conf has no listen_addresses override"; fi
check_eq "psql connection succeeds" "1" "$(psq labdb 'SELECT 1' 2>/dev/null)"
finish
