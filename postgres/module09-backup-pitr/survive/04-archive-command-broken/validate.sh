#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/04-archive-command-broken
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-04; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; finish; exit 1; fi
ac=$(psq postgres "show archive_command" 2>/dev/null)
if [[ -n "$ac" && "$ac" != "/bin/false"* && "$ac" != *"false"* ]]; then ok "archive_command is no longer a failing command"; else bad "archive_command is no longer a failing command (got ${ac:-<empty>})"; fi
r=$(psq postgres "select case when last_archived_time is not null and (last_failed_time is null or last_archived_time > last_failed_time) then 'ok' else 'failing' end from pg_stat_archiver" 2>/dev/null)
check_eq "archiver is succeeding (last archive newer than last failure)" "ok" "$r"
finish
