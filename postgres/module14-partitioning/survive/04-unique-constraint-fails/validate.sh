#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/04-unique-constraint-fails
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-04
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
c=$(psq stepup_store "select count(*) from pg_constraint c where c.conrelid=to_regclass('orders_chaos4') and c.contype in ('u','p') and (select count(*) from pg_attribute a where a.attrelid=c.conrelid and a.attnum = any(c.conkey) and a.attname in ('order_id','order_date')) = 2" 2>/dev/null)
if [[ -n "$c" && "$c" -ge 1 ]]; then ok "UNIQUE constraint on orders_chaos4 includes order_id and order_date"; else bad "UNIQUE constraint on orders_chaos4 includes order_id and order_date (found ${c:-<none>})"; fi
ins() { printf "INSERT INTO orders_chaos4 (order_id, customer_id, order_date, status, total_amount, region) VALUES (99999900, %s, '%s', 'pending', 1.00, 'West');" "$1" "$2"; }
out=$(try_sql stepup_store "$(ins 1 2024-01-15)
$(ins 2 2024-01-15)")
if grep -q 'duplicate key value violates unique constraint' <<<"$out"; then ok "duplicate (order_id, order_date) insert is rejected"; else bad "duplicate (order_id, order_date) insert is rejected (got: ${out:-no error})"; fi
out=$(try_sql stepup_store "$(ins 1 2024-01-15)
$(ins 1 2024-02-15)")
if [[ -z "$out" ]]; then ok "same order_id with a different order_date is allowed"; else bad "same order_id with a different order_date is allowed (got: $(head -1 <<<"$out"))"; fi
finish
