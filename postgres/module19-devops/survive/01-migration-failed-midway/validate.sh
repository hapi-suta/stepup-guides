#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/01-migration-failed-midway
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
DB=migrate_chaos
s=$(psq "$DB" "select success from schema_migrations where version=2" 2>/dev/null)
check_eq "migration V2 is marked successful" "t" "$s"
d=$(psq "$DB" "select count(*) from departments" 2>/dev/null)
if [[ "${d:-0}" -gt 0 ]]; then ok "departments is populated ($d rows)"; else bad "departments is populated (got ${d:-0} rows)"; fi
u=$(psq "$DB" "select count(*) from employees e where e.department is not null and not exists (select 1 from departments d where d.id=e.department_id and d.name=e.department)" 2>/dev/null)
check_eq "employees without a matching department_id" "0" "${u:-x}"
f=$(psq "$DB" "select count(*) from pg_constraint where conrelid='employees'::regclass and contype='f' and confrelid='departments'::regclass" 2>/dev/null)
check_eq "foreign key employees -> departments exists" "1" "${f:-0}"
finish
