#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/08-wal-directory-missing
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
STATE_DIR=/var/lib/suta-survive/module04-08; mkdir -p "$STATE_DIR"

WAL="$PGDATA/pg_wal"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if [[ -d "$WAL/" ]]; then ok "pg_wal directory is accessible"; else bad "pg_wal directory is accessible"; fi
nw=$(find "$WAL/" -maxdepth 1 -type f -name '[0-9A-F]*' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$nw" -ge 1 ]]; then ok "WAL files exist in pg_wal ($nw)"; else bad "WAL files exist in pg_wal (expected >= 1, got $nw)"; fi
lsn=$(psq labdb 'SELECT pg_current_wal_lsn()' 2>/dev/null)
if [[ -n "$lsn" ]]; then ok "server reports a current WAL position ($lsn)"; else bad "server reports a current WAL position"; fi
check_eq "psql connection succeeds" "1" "$(psq labdb 'SELECT 1' 2>/dev/null)"
finish
