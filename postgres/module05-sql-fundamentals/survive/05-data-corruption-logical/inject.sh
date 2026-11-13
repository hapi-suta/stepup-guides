#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/05-data-corruption-logical
# inject.sh - breaks the lab (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module05-05; mkdir -p "$STATE_DIR"

[[ -x "$PGBIN/postgres" ]] || { say "postgresql-16 is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
DB=stepup_store
psq "$DB" "$(cat <<'SQL'
DROP TABLE IF EXISTS employees, departments CASCADE;
CREATE TABLE departments (dept_id int PRIMARY KEY, dept_name text NOT NULL);
CREATE TABLE employees (
  emp_id int PRIMARY KEY, emp_name text NOT NULL, dept_id int, email text, hire_date date,
  CONSTRAINT employees_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES departments (dept_id));
INSERT INTO departments VALUES (1, 'Engineering'), (2, 'Sales'), (3, 'Support'), (4, 'Finance');
INSERT INTO employees VALUES
  (1, 'Alice Chen', 1, 'alice@company.com', '2023-01-15'), (2, 'Bob Martinez', 2, 'bob@company.com', '2023-02-01'),
  (3, 'Carol Davis', 1, 'carol@company.com', '2023-03-10'), (4, 'Dave Kim', 3, 'dave@company.com', '2023-05-20'),
  (5, 'Eve Johnson', 4, 'eve@company.com', '2023-06-30');
ALTER TABLE employees DISABLE TRIGGER ALL;
INSERT INTO employees VALUES
  (6, 'Ghost Worker 1', 99, 'ghost1@company.com', '2024-03-01'), (7, 'Ghost Worker 2', 88, 'ghost2@company.com', '2024-03-02'),
  (8, 'Ghost Worker 3', 77, 'ghost3@company.com', '2024-03-03'), (9, 'Alice Chen Copy', 1, 'alice@company.com', '2024-04-01');
SQL
)" >/dev/null || { say "seeding failed"; exit 1; }
say "employees: $(psq "$DB" 'SELECT count(*) FROM employees') rows, departments: $(psq "$DB" 'SELECT count(*) FROM departments') rows"
say ""
say 'ALERT: Data integrity errors detected.'
say 'The nightly reconciliation job is reporting mismatched employee-department'
say 'records. Some employees reference departments that do not exist. Duplicate'
say 'email addresses found in the employees table.'
exit 0
