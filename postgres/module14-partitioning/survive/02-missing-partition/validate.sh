#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/02-missing-partition
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-02
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
check_eq "orders_chaos2_2024_03 partition exists" "1" "$(psq stepup_store "select count(*) from pg_inherits where inhparent=to_regclass('orders_chaos2') and inhrelid=to_regclass('orders_chaos2_2024_03')" 2>/dev/null)"
out=$(try_sql stepup_store "INSERT INTO orders_chaos2 (order_id, customer_id, order_date, status, total_amount, region) VALUES (99997, 1, '2024-03-15', 'pending', 1.00, 'West') RETURNING tableoid::regclass::text;")
if [[ "$out" == "orders_chaos2_2024_03" ]]; then ok "insert of a March 2024 row succeeds and lands in the March partition"; else bad "insert of a March 2024 row succeeds (got: $(head -1 <<<"$out"))"; fi
m=$(psq stepup_store "select count(*) from orders_chaos2 where order_date >= '2024-03-01' and order_date < '2024-04-01'" 2>/dev/null)
if [[ -n "$m" && "$m" -ge 1 ]]; then ok "March partition has rows ($m)"; else bad "March partition has rows (got ${m:-<none>})"; fi
finish
