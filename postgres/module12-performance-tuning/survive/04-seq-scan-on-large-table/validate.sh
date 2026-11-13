#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/04-seq-scan-on-large-table
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-04
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
check_eq "enable_indexscan is on" "on" "$(psq stepup_store 'show enable_indexscan' 2>/dev/null)"
check_eq "enable_bitmapscan is on" "on" "$(psq stepup_store 'show enable_bitmapscan' 2>/dev/null)"
plan=$(psq stepup_store "explain select * from perf_probe where customer_id = 1" 2>/dev/null)
if grep -qE 'Index (Only )?Scan|Bitmap' <<<"$plan"; then ok "EXPLAIN shows an Index Scan or Bitmap Index Scan"; else bad "EXPLAIN shows an Index Scan or Bitmap Index Scan (got: $(head -1 <<<"$plan"))"; fi
if grep -Eq '^(enable_indexscan|enable_bitmapscan) *=' "$PGDATA/postgresql.auto.conf" 2>/dev/null; then bad "postgresql.auto.conf has no enable_indexscan/enable_bitmapscan overrides"; else ok "postgresql.auto.conf has no enable_indexscan/enable_bitmapscan overrides"; fi
finish
