#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/05-data-checksums-mismatch
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
STATE_DIR=/var/lib/suta-survive/module04-05; mkdir -p "$STATE_DIR"

check_eq "main PostgreSQL (5432) is running" "active" "$(systemctl is-active postgresql-16)"
check_eq "main PostgreSQL accepts connections" "1" "$(psq labdb 'SELECT 1' 2>/dev/null)"
if sudo -u postgres "$PGBIN/pg_isready" -q -p 5437; then bad "corrupt test cluster (5437) is stopped"; else ok "corrupt test cluster (5437) is stopped"; fi
if [[ -e /opt/pgsql/data-checksum ]]; then bad "corrupt cluster data directory removed"; else ok "corrupt cluster data directory removed"; fi
check_eq "main PostgreSQL is fully functional" "t" "$(psq labdb 'SELECT count(*) >= 1 FROM pg_stat_activity' 2>/dev/null)"
finish
