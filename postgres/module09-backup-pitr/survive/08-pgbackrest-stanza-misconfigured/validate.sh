#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/08-pgbackrest-stanza-misconfigured
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-08; mkdir -p "$STATE_DIR"
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

CONF=/etc/pgbackrest/pgbackrest.conf
grep -q '^\[main\]' "$CONF" && ok "pgbackrest.conf has a [main] stanza section" || bad "pgbackrest.conf has a [main] stanza section (expected [main], not found)"
check_eq "pg1-path is /opt/pgsql/data" "/opt/pgsql/data" "$(grep -E '^pg1-path=' "$CONF" | head -1 | cut -d= -f2)"
if pbr --stanza=main check >/dev/null 2>&1; then ok "pgbackrest --stanza=main check succeeds"; else bad "pgbackrest --stanza=main check succeeds"; fi
if pbr --stanza=main info 2>&1 | grep -q 'status: ok'; then ok "pgbackrest info reports status ok for stanza main"; else bad "pgbackrest info reports status ok for stanza main"; fi
finish
