#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/08-replication-after-upgrade
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-08; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

RF=/opt/pgsql/replica_status/replica_info.conf
if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; finish; exit 1; fi
check_eq "stale slot chaos8_replica_slot is removed" "0" "$(psq postgres "select count(*) from pg_replication_slots where slot_name='chaos8_replica_slot'" 2>/dev/null)"
rv=$(grep -E '^replica_pg_version=' "$RF" 2>/dev/null | cut -d= -f2); pv=$(grep -E '^primary_pg_version=' "$RF" 2>/dev/null | cut -d= -f2)
if [[ "$rv" == "16" && "$pv" == "16" ]]; then ok "replica_info.conf shows matching versions (both 16)"; else bad "replica_info.conf shows matching versions (expected 16/16, got ${rv:-<none>}/${pv:-<none>})"; fi
check_eq "wal_level is replica" "replica" "$(psq postgres 'show wal_level' 2>/dev/null)"
n=$(psq postgres "select count(*) from pg_replication_slots where slot_type='physical' and slot_name <> 'chaos8_replica_slot'" 2>/dev/null)
[[ "${n:-0}" -ge 1 ]] && ok "a new physical replication slot exists" || bad "a new physical replication slot exists (expected >=1, got ${n:-0})"
finish
