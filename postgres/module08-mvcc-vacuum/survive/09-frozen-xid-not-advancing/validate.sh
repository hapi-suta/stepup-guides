#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/09-frozen-xid-not-advancing
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-09
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
check_lt "xid_freeze_demo relfrozenxid age is below 1000" 1000 "$(psq stepup_store "SELECT age(relfrozenxid) FROM pg_class WHERE relname='xid_freeze_demo'")"
opts=$(psq stepup_store "SELECT COALESCE(reloptions::text,'none') FROM pg_class WHERE relname='xid_freeze_demo'")
if [[ -n "$opts" && "$opts" != *autovacuum_enabled=false* ]]; then ok "autovacuum is re-enabled on the table ($opts)"; else bad "autovacuum is re-enabled on the table (reloptions: ${opts:-<empty>})"; fi
check_eq "dead tuples cleaned" "0" "$(psq stepup_store "SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='xid_freeze_demo'")"
pg_up && ok "PostgreSQL accepts connections" || bad "PostgreSQL accepts connections"
finish
