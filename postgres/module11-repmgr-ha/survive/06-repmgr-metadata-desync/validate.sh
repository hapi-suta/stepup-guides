#!/usr/bin/env bash
# SUTA survive scenario: module11-repmgr-ha/06-repmgr-metadata-desync
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
NID=$(sed -n "s/^node_id=\([0-9][0-9]*\).*/\1/p" "$CONF" 2>/dev/null | head -1)
check_eq "this node is the real primary" "f" "$(psq postgres 'select pg_is_in_recovery()' 2>/dev/null)"
check_eq "repmgr.nodes lists this node as primary" "primary" "$(psq repmgr "select type from repmgr.nodes where node_id=${NID:-0}" 2>/dev/null)"
check_eq "no other data node is registered as primary" "0" "$(psq repmgr "select count(*) from repmgr.nodes where type='primary' and node_id<>${NID:-0}" 2>/dev/null)"
check_eq "this node is registered active" "t" "$(psq repmgr "select active from repmgr.nodes where node_id=${NID:-0}" 2>/dev/null)"
finish
