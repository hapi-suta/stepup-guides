#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/07-ansible-breaks-pg-hba
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
HBA="$PGDATA/pg_hba.conf"
n=$(psq postgres "select count(*) from pg_hba_file_rules where type like 'host%' and auth_method='reject'" 2>/dev/null)
check_eq "host rules using reject" "0" "${n:-x}"
e=$(psq postgres "select count(*) from pg_hba_file_rules where error is not null" 2>/dev/null)
check_eq "pg_hba.conf rules with errors" "0" "${e:-x}"
h=$(psq postgres "select count(*) from pg_hba_file_rules where type='host' and address in ('127.0.0.1','127.0.0.1/32') and auth_method <> 'reject'" 2>/dev/null)
if [[ "${h:-0}" -ge 1 ]]; then ok "127.0.0.1 TCP rule present"; else bad "127.0.0.1 TCP rule present (got ${h:-0})"; fi
mt=$(stat -c %Y "$HBA" 2>/dev/null)
l=$(psq postgres "select pg_conf_load_time() >= to_timestamp(${mt:-0})" 2>/dev/null)
check_eq "configuration reloaded after the last pg_hba.conf edit" "t" "$l"
out=$(sudo -u postgres env PGCONNECT_TIMEOUT=5 "$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U postgres -d postgres -w -tAXqc "select 1" 2>&1)
if [[ "$out" == *"rejects connection"* ]]; then bad "TCP connection is no longer rejected by pg_hba.conf"; else ok "TCP connection is no longer rejected by pg_hba.conf"; fi
finish
