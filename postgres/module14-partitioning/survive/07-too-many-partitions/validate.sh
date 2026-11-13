#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/07-too-many-partitions
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-07
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
p=$(psq stepup_store "select count(*) from pg_inherits where inhparent=to_regclass('chaos7_metrics')" 2>/dev/null)
if [[ -n "$p" && "$p" -ge 1 && "$p" -lt 200 ]]; then ok "partition count is under 200 ($p)"; else bad "partition count is under 200 (got ${p:-<none>})"; fi
best=""
for _ in 1 2 3; do
  t=$(psq stepup_store "explain (summary on, costs off) select * from chaos7_metrics where metric_date = '2023-06-15'" 2>/dev/null | awk '/Planning Time/{print $3}')
  [[ -n "$t" ]] && { [[ -z "$best" ]] && best="$t" || best=$(awk -v a="$best" -v b="$t" 'BEGIN{print (b<a)?b:a}'); }
done
if [[ -n "$best" ]] && awk -v v="$best" 'BEGIN{exit !(v<50)}'; then ok "planning time for a single-date query is under 50ms (${best}ms)"; else bad "planning time for a single-date query is under 50ms (got ${best:-<none>}ms)"; fi
exp=$(cat "$STATE_DIR/rows" 2>/dev/null || echo 10000)
check_eq "data is intact (row count matches)" "$exp" "$(psq stepup_store 'select count(*) from chaos7_metrics' 2>/dev/null)"
finish
