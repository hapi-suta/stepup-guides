#!/usr/bin/env bash
# SUTA survive scenario: module11-streaming-replication/07-archive-command-failure
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

ARC=/opt/pgsql/archive
check_eq "archive directory is not mode 000" "ok" "$([[ "$(stat -c %a "$ARC" 2>/dev/null)" != "0" ]] && echo ok || echo locked)"
if sudo -u postgres test -w "$ARC" -a -x "$ARC"; then ok "postgres can write to the archive directory"; else bad "postgres can write to the archive directory"; fi
good=$(psq postgres "select (last_archived_time is not null and (last_failed_time is null or last_archived_time >= last_failed_time)) from pg_stat_archiver" 2>/dev/null)
check_eq "last archive attempt succeeded (archived time >= failed time)" "t" "$good"
check_eq "archive_mode is on" "on" "$(psq postgres 'show archive_mode' 2>/dev/null)"
finish
