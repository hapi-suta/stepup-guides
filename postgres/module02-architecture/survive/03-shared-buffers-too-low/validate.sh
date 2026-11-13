#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/03-shared-buffers-too-low
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
SB=$(psq postgres "SELECT setting::int FROM pg_settings WHERE name='shared_buffers'" 2>/dev/null)
if [[ -n "$SB" && "$SB" -ge 4096 ]]; then ok "shared_buffers is at least 32MB ($((SB * 8 / 1024))MB in effect)"; else bad "shared_buffers is at least 32MB (expected >= 4096 blocks, got ${SB:-<empty>})"; fi
PR=$(psq postgres "SELECT pending_restart FROM pg_settings WHERE name='shared_buffers'" 2>/dev/null)
check_eq "no restart is pending for shared_buffers" "f" "$PR"
finish
