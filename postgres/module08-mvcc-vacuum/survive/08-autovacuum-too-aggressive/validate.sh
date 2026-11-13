#!/usr/bin/env bash
# SUTA survive scenario: module08-mvcc-vacuum/08-autovacuum-too-aggressive
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module08-08
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
nap=$(psq postgres "SELECT setting FROM pg_settings WHERE name='autovacuum_naptime'")
check_ge "autovacuum_naptime is 60s or more" 60 "$nap"
cd_=$(psq postgres "SELECT setting FROM pg_settings WHERE name='autovacuum_vacuum_cost_delay'")
[[ "$cd_" =~ ^[0-9.]+$ ]] && awk -v v="$cd_" 'BEGIN{exit !(v>0)}' && ok "autovacuum_vacuum_cost_delay is greater than 0" || bad "autovacuum_vacuum_cost_delay is greater than 0 (got ${cd_:-<empty>})"
cl=$(psq postgres "SELECT setting FROM pg_settings WHERE name='autovacuum_vacuum_cost_limit'")
[[ "$cl" == "-1" || "$cl" == "200" ]] && ok "autovacuum_vacuum_cost_limit is default ($cl)" || bad "autovacuum_vacuum_cost_limit is default (expected -1 or 200, got ${cl:-<empty>})"
sf=$(psq postgres "SELECT setting FROM pg_settings WHERE name='autovacuum_vacuum_scale_factor'")
[[ "$sf" =~ ^[0-9.]+$ ]] && awk -v v="$sf" 'BEGIN{exit !(v>=0.1)}' && ok "autovacuum_vacuum_scale_factor is 0.1 or higher" || bad "autovacuum_vacuum_scale_factor is 0.1 or higher (got ${sf:-<empty>})"
pg_up && ok "PostgreSQL accepts connections" || bad "PostgreSQL accepts connections"
finish
