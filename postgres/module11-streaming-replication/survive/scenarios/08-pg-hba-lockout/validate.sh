#!/usr/bin/env bash
# SUTA survive scenario: module11-streaming-replication/08-pg-hba-lockout
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

check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
rules=$(psq postgres "select count(*) from pg_hba_file_rules where type like 'host%' and 'replication'=any(database) and ('replicator'=any(user_name) or 'all'=any(user_name)) and auth_method<>'reject' and error is null" 2>/dev/null)
if [[ "${rules:-0}" -ge 1 ]]; then ok "pg_hba.conf has a host replication rule for the replicator role"; else bad "pg_hba.conf has a host replication rule for the replicator role (got ${rules:-0})"; fi
n=0
for _ in $(seq 1 20); do n=$(psq postgres "select count(*) from pg_stat_replication where state='streaming'" 2>/dev/null); [[ "${n:-0}" -ge 1 ]] && break; sleep 1; done
if [[ "${n:-0}" -ge 1 ]]; then ok "standby is streaming"; else bad "standby is streaming (expected >=1 streaming row, got ${n:-0})"; fi
finish
