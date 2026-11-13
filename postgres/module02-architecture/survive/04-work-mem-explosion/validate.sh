#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/04-work-mem-explosion
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

if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; finish; exit 1; fi
WM=$(psq postgres "SELECT setting::bigint FROM pg_settings WHERE name='work_mem'" 2>/dev/null)
if [[ -n "$WM" && "$WM" -le 262144 ]]; then ok "work_mem is 256MB or less (${WM}kB)"; else bad "work_mem is 256MB or less (expected <= 262144kB, got ${WM:-<empty>})"; fi
RUN=$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%chaos_sort_data%' AND pid <> pg_backend_pid()" 2>/dev/null)
check_eq "No runaway sort sessions remain" "0" "$RUN"
AVAIL=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
if [[ "$AVAIL" -ge 100 ]]; then ok "System has reasonable free memory (${AVAIL}MB available)"; else bad "System has reasonable free memory (expected >= 100MB, got ${AVAIL}MB)"; fi
finish
