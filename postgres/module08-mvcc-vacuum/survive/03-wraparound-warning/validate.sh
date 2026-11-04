#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/03-wraparound-warning
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-03
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
if grep -Eq '^[[:space:]]*autovacuum_freeze_max_age[[:space:]]*=' "$PGDATA/postgresql.auto.conf" 2>/dev/null; then
  bad "autovacuum_freeze_max_age override removed from postgresql.auto.conf"; else ok "autovacuum_freeze_max_age override removed from postgresql.auto.conf"; fi
# the setting is postmaster-level: after RESET + reload it is either already 200000000 or flagged pending restart
live=$(psq postgres "SELECT setting || '/' || pending_restart FROM pg_settings WHERE name='autovacuum_freeze_max_age'")
if [[ "$live" == "200000000/f" || "$live" == "200000000/false" || "$live" == */t || "$live" == */true ]]; then ok "autovacuum_freeze_max_age restored to 200000000 (live: $live)"; else bad "autovacuum_freeze_max_age restored to 200000000 (got ${live:-<empty>})"; fi
check_eq "vacuum_freeze_min_age restored to 50000000" "50000000" "$(psq postgres "SHOW vacuum_freeze_min_age")"
check_lt "freeze_needed relfrozenxid age below 10000" 10000 "$(psq stepup_store "SELECT age(relfrozenxid) FROM pg_class WHERE relname='freeze_needed'")"
pg_up && ok "PostgreSQL accepts connections" || bad "PostgreSQL accepts connections"
finish
