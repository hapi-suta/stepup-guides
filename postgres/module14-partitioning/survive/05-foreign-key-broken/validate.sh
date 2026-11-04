#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/05-foreign-key-broken
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-05
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

# run SQL inside BEGIN..ROLLBACK (nothing persists); prints output and errors
try_sql() { printf 'BEGIN;\n%s\nROLLBACK;\n' "$2" | sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXq 2>&1; }
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
check_eq "chaos5_orders_2024_02 is attached as a partition" "1" "$(psq stepup_store "select count(*) from pg_inherits where inhparent=to_regclass('chaos5_orders') and inhrelid=to_regclass('chaos5_orders_2024_02')" 2>/dev/null)"
f=$(psq stepup_store "select count(*) from chaos5_orders where order_date >= '2024-02-01' and order_date < '2024-03-01'" 2>/dev/null)
if [[ -n "$f" && "$f" -ge 1 ]]; then ok "February orders are visible through the parent table ($f)"; else bad "February orders are visible through the parent table (got ${f:-<none>})"; fi
li=$(psq stepup_store "select count(*) from chaos5_line_items" 2>/dev/null)
jn=$(psq stepup_store "select count(*) from chaos5_line_items li join chaos5_orders o on o.id=li.order_id and o.order_date=li.order_date" 2>/dev/null)
check_eq "every line item joins back to its order" "$li" "$jn"
out=$(try_sql stepup_store "INSERT INTO chaos5_line_items (order_id, order_date, product_name, quantity) SELECT id, order_date, 'Validate Probe', 1 FROM chaos5_orders WHERE order_date >= '2024-02-01' AND order_date < '2024-03-01' LIMIT 1;")
if [[ -z "$out" ]]; then ok "new FK insert for a February order succeeds"; else bad "new FK insert for a February order succeeds (got: $(head -1 <<<"$out"))"; fi
finish
