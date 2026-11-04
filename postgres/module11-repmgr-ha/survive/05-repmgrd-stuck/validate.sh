#!/usr/bin/env bash
# SUTA survive scenario: module11-repmgr-ha/05-repmgrd-stuck
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

CONF=/etc/repmgr/16/repmgr.conf
check_eq "repmgr-16 service is active" "active" "$(systemctl is-active repmgr-16)"
if pgrep -x repmgrd >/dev/null; then ok "repmgrd process is running"; else bad "repmgrd process is running"; fi
if grep -q '^node_id=' "$CONF" 2>/dev/null && grep -q '^conninfo=' "$CONF" 2>/dev/null; then ok "repmgr.conf has node_id and conninfo"; else bad "repmgr.conf has node_id and conninfo"; fi
if sudo -u postgres /usr/pgsql-16/bin/repmgr -f "$CONF" cluster show >/dev/null 2>&1; then ok "repmgr cluster show succeeds"; else bad "repmgr cluster show succeeds"; fi
finish
