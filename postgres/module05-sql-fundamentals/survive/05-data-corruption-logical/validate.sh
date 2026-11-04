#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/05-data-corruption-logical
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module05-05; mkdir -p "$STATE_DIR"

DB=stepup_store
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "employees and departments tables exist" "employees/departments" "$(psq "$DB" "SELECT coalesce(to_regclass('public.employees')::text,'-') || '/' || coalesce(to_regclass('public.departments')::text,'-')" 2>/dev/null)"
n=$(psq "$DB" 'SELECT count(*) FROM employees' 2>/dev/null)
if [[ "$n" =~ ^[0-9]+$ && "$n" -ge 5 ]]; then ok "legitimate employee rows are still there ($n)"; else bad "legitimate employee rows are still there (expected >= 5, got ${n:-<none>})"; fi
check_eq "no orphaned employee records" "0" "$(psq "$DB" 'SELECT count(*) FROM employees e LEFT JOIN departments d ON e.dept_id = d.dept_id WHERE d.dept_id IS NULL' 2>/dev/null)"
check_eq "no duplicate emails" "0" "$(psq "$DB" 'SELECT count(*) FROM (SELECT email FROM employees GROUP BY email HAVING count(*) > 1) x' 2>/dev/null)"
check_eq "FK employees_dept_id_fkey exists and is validated" "t" "$(psq "$DB" "SELECT convalidated FROM pg_constraint WHERE conname = 'employees_dept_id_fkey' AND conrelid = 'public.employees'::regclass" 2>/dev/null)"
check_eq "no disabled triggers on employees (FK enforced)" "0/2" "$(psq "$DB" "SELECT count(*) FILTER (WHERE tgenabled <> 'O') || '/' || count(*) FROM pg_trigger WHERE tgrelid = 'public.employees'::regclass" 2>/dev/null)"
finish
