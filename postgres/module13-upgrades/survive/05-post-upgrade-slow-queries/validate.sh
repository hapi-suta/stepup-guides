#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/05-post-upgrade-slow-queries
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-05; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; finish; exit 1; fi
for t in chaos13_orders chaos13_customers; do
  n=$(psq stepup_store "select count(*) from pg_statistic where starelid = '$t'::regclass" 2>/dev/null)
  [[ "${n:-0}" -gt 0 ]] && ok "pg_statistic has entries for $t" || bad "pg_statistic has entries for $t (expected >0, got ${n:-<none>})"
  la=$(psq stepup_store "select count(*) from pg_stat_user_tables where relname = '$t' and (last_analyze is not null or last_autoanalyze is not null)" 2>/dev/null)
  check_eq "last_analyze is set for $t" "1" "${la:-0}"
done
actual=$(psq stepup_store "select count(*) from chaos13_orders where status = 'pending'" 2>/dev/null)
plan=$(psq stepup_store "explain select * from chaos13_orders where status = 'pending'" 2>/dev/null | head -1)
est=""; [[ "$plan" =~ rows=([0-9]+) ]] && est="${BASH_REMATCH[1]}"
if [[ -n "$est" && -n "$actual" && "$actual" -gt 0 ]] && (( est * 2 >= actual && est <= actual * 2 )); then
  ok "EXPLAIN row estimate ($est) is within 2x of actual ($actual)"
else
  bad "EXPLAIN row estimate is within 2x of actual (expected ~${actual:-?}, got ${est:-<none>})"
fi
finish
