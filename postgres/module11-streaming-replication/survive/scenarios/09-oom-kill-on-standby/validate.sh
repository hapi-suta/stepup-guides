#!/usr/bin/env bash
# SUTA-NODE: 2
# SUTA survive scenario: module11-streaming-replication/09-oom-kill-on-standby
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
check_eq "standby is in recovery" "t" "$(psq postgres 'select pg_is_in_recovery()' 2>/dev/null)"
st=""
for _ in $(seq 1 15); do st=$(psq postgres "select status from pg_stat_wal_receiver" 2>/dev/null); [[ "$st" == streaming ]] && break; sleep 1; done
check_eq "WAL receiver is streaming from the primary" "streaming" "$st"
finish
