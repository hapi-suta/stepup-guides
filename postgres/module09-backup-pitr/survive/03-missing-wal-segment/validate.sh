#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/03-missing-wal-segment
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-03; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

cd /
pbr() { sudo -u postgres pgbackrest "$@"; }

S=$(cat /var/lib/suta-survive/module09-03/segment 2>/dev/null)
if [[ -z "$S" ]]; then bad "inject state found (run inject.sh first)"; finish; exit 1; fi
f=$(find /opt/pgsql/backup/pgbackrest/archive/main -type f -name "$S-*" 2>/dev/null | head -1)
if [[ -n "$f" ]]; then ok "WAL segment $S is back in the archive"; else bad "WAL segment $S is back in the archive (expected present, got missing)"; fi
if timeout 25 sudo -u postgres pgbackrest --stanza=main verify >/dev/null 2>&1; then ok "pgbackrest verify reports no errors"; else bad "pgbackrest verify reports no errors (expected rc 0, got failure)"; fi
finish
