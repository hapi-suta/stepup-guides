#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/09-full-cluster-recovery
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-09; mkdir -p "$STATE_DIR"
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

check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; finish; exit 1; fi
[[ -f /opt/pgsql/data/PG_VERSION ]] && ok "data directory /opt/pgsql/data is populated" || bad "data directory /opt/pgsql/data is populated"
check_eq "cluster is out of recovery (promoted)" "f" "$(psq postgres 'select pg_is_in_recovery()' 2>/dev/null)"
check_eq "stepup_store database exists" "1" "$(psq postgres "select count(*) from pg_database where datname='stepup_store'" 2>/dev/null)"
want=$(cat /var/lib/suta-survive/module09-09/employees_count 2>/dev/null); want=${want:-10000}
n=$(psq stepup_store "select count(*) from employees" 2>/dev/null)
if [[ -n "$n" && "$n" -ge "$want" ]]; then ok "employees has at least $want rows ($n)"; else bad "employees has at least $want rows (expected >=$want, got ${n:-<none>})"; fi
if pbr --stanza=main check >/dev/null 2>&1; then ok "pgbackrest check succeeds (archiving works)"; else bad "pgbackrest check succeeds (archiving works)"; fi
finish
