#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/06-exporter-permission-denied
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
m=$(psq postgres "select pg_has_role('postgres_exporter','pg_monitor','member')" 2>/dev/null)
check_eq "postgres_exporter is a member of pg_monitor" "t" "$m"
check_eq "postgres_exporter service is active" "active" "$(systemctl is-active postgres_exporter)"
v=""; for _ in 1 2 3 4 5; do v=$(curl -s -m 3 http://localhost:9187/metrics | awk '/^pg_up /{print $2}'); [[ "$v" == "1" ]] && break; sleep 1; done
check_eq "exporter reports pg_up 1" "1" "$v"
n=$(curl -s -m 3 http://localhost:9187/metrics | grep -c '^pg_stat_activity_count')
if [[ "$n" -gt 0 ]]; then ok "pg_stat_activity_count metrics are exported ($n series)"; else bad "pg_stat_activity_count metrics are exported (got 0 series)"; fi
finish
