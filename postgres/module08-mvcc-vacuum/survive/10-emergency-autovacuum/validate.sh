#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/10-emergency-autovacuum
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-10
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
pg_up && ok "PostgreSQL is running" || bad "PostgreSQL is running"
check_eq "autovacuum_freeze_max_age is at default (200000000)" "200000000" "$(psq postgres "SHOW autovacuum_freeze_max_age")"
check_eq "vacuum_freeze_table_age is at default (150000000)" "150000000" "$(psq postgres "SHOW vacuum_freeze_table_age")"
check_eq "No emergency autovacuum running" "0" "$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE query LIKE 'autovacuum:%to prevent wraparound%'")"
pg_up && ok "PostgreSQL accepts connections" || bad "PostgreSQL accepts connections"
finish
