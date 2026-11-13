#!/usr/bin/env bash
# SUTA survive scenario: module10-monitoring/07-shared-preload-crash
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module10-07
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2" 2>/dev/null; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
# check_lt desc limit actual : PASS when actual is an integer below limit
check_lt() { local d="$1" l="$2" a="$3"; [[ "$a" =~ ^[0-9]+$ && "$a" -lt "$l" ]] && ok "$d" || bad "$d (expected < $l, got ${a:-<empty>})"; }
# check_ge desc limit actual : PASS when actual is an integer >= limit
check_ge() { local d="$1" l="$2" a="$3"; [[ "$a" =~ ^-?[0-9]+$ && "$a" -ge "$l" ]] && ok "$d" || bad "$d (expected >= $l, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
pg_up && ok "PostgreSQL accepts connections" || bad "PostgreSQL accepts connections"
if grep -q 'pg_fake_monitoring_lib' "$PGDATA/postgresql.auto.conf" 2>/dev/null; then bad "No bad libraries in postgresql.auto.conf"; else ok "No bad libraries in postgresql.auto.conf"; fi
spl=$(psq postgres "SHOW shared_preload_libraries")
if pg_up && [[ "$spl" != *pg_fake_monitoring_lib* ]]; then ok "shared_preload_libraries does not contain pg_fake_monitoring_lib (${spl:-empty})"; else bad "shared_preload_libraries does not contain pg_fake_monitoring_lib (got ${spl:-<unreadable>})"; fi
finish
