#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/08-monitoring-query-overhead
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
Q=/etc/postgres_exporter/queries.yaml
if grep -q 'pg_expensive_monitoring_query' "$Q" 2>/dev/null; then bad "pg_expensive_monitoring_query removed from queries.yaml"; else ok "pg_expensive_monitoring_query removed from queries.yaml"; fi
if grep -qi 'pg_sleep' "$Q" 2>/dev/null; then bad "no pg_sleep left in queries.yaml"; else ok "no pg_sleep left in queries.yaml"; fi
if python3 -c 'import yaml' 2>/dev/null; then
  if python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$Q" 2>/dev/null; then ok "queries.yaml is valid YAML"; else bad "queries.yaml is valid YAML"; fi
fi
s=$(psq postgres "select count(*) from pg_stat_activity where usename='postgres_exporter' and query ilike '%pg_sleep%' and pid<>pg_backend_pid()" 2>/dev/null)
check_eq "no pg_sleep session from postgres_exporter" "0" "${s:-x}"
finish
