#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/01-accidental-table-drop
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-01; mkdir -p "$STATE_DIR"
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

if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; finish; exit 1; fi
want=$(cat /var/lib/suta-survive/module09-01/employees_count 2>/dev/null); want=${want:-10000}
n=$(psq stepup_store "select count(*) from employees" 2>/dev/null)
if [[ -n "$n" ]]; then ok "employees table exists in stepup_store"; else bad "employees table exists in stepup_store (query failed)"; fi
if [[ -n "$n" && "$n" -ge "$want" ]]; then ok "employees has at least $want rows ($n)"; else bad "employees has at least $want rows (expected >=$want, got ${n:-<none>})"; fi
finish
