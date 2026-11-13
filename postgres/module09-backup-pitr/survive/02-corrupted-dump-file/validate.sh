#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/02-corrupted-dump-file
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-02; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

F=/opt/pgsql/backup/dumps/stepup_store.custom
if [[ -s "$F" ]] && sudo -u postgres "$PGBIN/pg_restore" --list "$F" >/dev/null 2>&1; then ok "pg_restore --list reads $F"; else bad "pg_restore --list reads $F (expected a valid archive, got an error or missing file)"; fi
t=$(sudo -u postgres "$PGBIN/pg_restore" --list "$F" 2>/dev/null | grep -c ' TABLE ')
[[ "${t:-0}" -ge 1 ]] && ok "dump table of contents lists tables ($t)" || bad "dump table of contents lists tables (expected >=1, got ${t:-0})"
d=$(sudo -u postgres "$PGBIN/pg_restore" --list "$F" 2>/dev/null | grep -c ' TABLE DATA ')
[[ "${d:-0}" -ge 1 ]] && ok "dump contains table data ($d)" || bad "dump contains table data (expected >=1, got ${d:-0})"
finish
