#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/01-connection-exhaustion
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
MAXC=$(psq postgres "SELECT setting::int FROM pg_settings WHERE name='max_connections'" 2>/dev/null)
CUR=$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE backend_type='client backend'" 2>/dev/null)
if [[ -n "$CUR" && -n "$MAXC" && "$CUR" -lt $((MAXC * 8 / 10)) ]]; then ok "Connection count ($CUR) is below 80% of max_connections ($MAXC)"; else bad "Connection count is below 80% of max_connections (expected < $((MAXC * 8 / 10)), got ${CUR:-<empty>})"; fi
if [[ "$(psq labdb "SELECT 'connection works'" 2>/dev/null)" == "connection works" ]]; then ok "New psql connection succeeded"; else bad "New psql connection succeeded"; fi
SL=$(psq postgres "SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%pg_sleep%' AND pid <> pg_backend_pid()" 2>/dev/null)
check_eq "No pg_sleep sessions remain" "0" "$SL"
finish
