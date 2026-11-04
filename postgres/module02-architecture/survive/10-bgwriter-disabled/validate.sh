#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/10-bgwriter-disabled
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
BG=$(psq postgres "SELECT setting FROM pg_settings WHERE name='bgwriter_lru_maxpages'" 2>/dev/null)
if [[ -n "$BG" && "$BG" -gt 0 ]]; then ok "bgwriter_lru_maxpages is non-zero ($BG)"; else bad "bgwriter_lru_maxpages is non-zero (got ${BG:-<empty>})"; fi
CT=$(psq postgres "SELECT setting FROM pg_settings WHERE name='checkpoint_timeout'" 2>/dev/null)
if [[ -n "$CT" && "$CT" -le 900 ]]; then ok "checkpoint_timeout is 15min or less (${CT}s)"; else bad "checkpoint_timeout is 15min or less (expected <= 900s, got ${CT:-<empty>})"; fi
finish
