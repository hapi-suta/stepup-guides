#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/06-runaway-query
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
STATE_DIR=/var/lib/suta-survive/module05-06; mkdir -p "$STATE_DIR"

DB=stepup_store
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "runaway_report_job is gone" "0" "$(psq "$DB" "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'runaway_report_job' AND state = 'active'" 2>/dev/null)"
check_eq "no active query has run longer than 5 minutes" "0" "$(psq "$DB" "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND pid <> pg_backend_pid() AND backend_type = 'client backend' AND now() - query_start > interval '5 minutes'" 2>/dev/null)"
st=$(psq "$DB" "SELECT coalesce((SELECT split_part(c, '=', 2) FROM unnest(s.setconfig) c WHERE c LIKE 'statement\_timeout=%' LIMIT 1), '') FROM pg_db_role_setting s JOIN pg_database d ON d.oid = s.setdatabase WHERE d.datname = 'stepup_store' AND s.setrole = 0" 2>/dev/null)
if [[ -n "$st" && "$st" != "0" ]]; then ok "statement_timeout is set on stepup_store ($st)"; else bad "statement_timeout is set on stepup_store (got ${st:-<unset>})"; fi
finish
