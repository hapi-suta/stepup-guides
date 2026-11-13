#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/03-work-mem-too-low
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-03
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
wm=$(psq stepup_store "select setting::bigint from pg_settings where name='work_mem'" 2>/dev/null)
if [[ -n "$wm" && "$wm" -ge 4096 ]]; then ok "work_mem is at least 4MB (${wm}kB)"; else bad "work_mem is at least 4MB (got ${wm:-<none>} kB)"; fi
plan=$(psq stepup_store "explain (analyze, costs off, timing off) select g from generate_series(1,50000) g order by random()" 2>&1)
if grep -q 'Sort Method: quicksort' <<<"$plan"; then ok "sort operation uses memory not disk"; else bad "sort operation uses memory not disk (got: $(grep -m1 'Sort Method' <<<"$plan"))"; fi
tfl=$(psq stepup_store "select setting::bigint from pg_settings where name='temp_file_limit'" 2>/dev/null)
if [[ "$tfl" == "-1" || ( -n "$tfl" && "$tfl" -ge 65536 ) ]]; then ok "temp_file_limit is not blocking queries ($tfl)"; else bad "temp_file_limit is not blocking queries (got ${tfl:-<none>})"; fi
if grep -Eq "^work_mem *= *'?64kB" "$PGDATA/postgresql.auto.conf" 2>/dev/null; then bad "postgresql.auto.conf no longer sets work_mem to 64kB"; else ok "postgresql.auto.conf no longer sets work_mem to 64kB"; fi
finish
