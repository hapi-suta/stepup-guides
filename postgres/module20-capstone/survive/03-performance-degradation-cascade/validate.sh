#!/usr/bin/env bash
# SUTA survive scenario: module20-capstone/03-performance-degradation-cascade
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
DB=appdb
sb=$(psq postgres "select setting::bigint*8/1024 from pg_settings where name='shared_buffers'" 2>/dev/null)
if [[ "${sb:-0}" -ge 512 ]]; then ok "shared_buffers is ${sb}MB"; else bad "shared_buffers (expected >= 512MB, got ${sb:-<empty>}MB)"; fi
pr=$(psq postgres "select pending_restart from pg_settings where name='shared_buffers'" 2>/dev/null)
check_eq "shared_buffers change applied (no pending restart)" "f" "$pr"
wm=$(psq postgres "select setting::bigint/1024 from pg_settings where name='work_mem'" 2>/dev/null)
if [[ "${wm:-0}" -ge 8 ]]; then ok "work_mem is ${wm}MB"; else bad "work_mem (expected >= 8MB, got ${wm:-<empty>}MB)"; fi
r=$(psq postgres "select setting::numeric <= 2 from pg_settings where name='random_page_cost'" 2>/dev/null)
check_eq "random_page_cost <= 2" "t" "$r"
e=$(psq postgres "select setting::bigint*8/1024 >= 1024 from pg_settings where name='effective_cache_size'" 2>/dev/null)
check_eq "effective_cache_size >= 1GB" "t" "$e"
ix=$(psq "$DB" "select count(*) from pg_indexes where schemaname='app' and indexname in ('idx_orders_customer_id','idx_orders_status','idx_order_items_order_id')" 2>/dev/null)
check_eq "dropped indexes recreated" "3" "${ix:-0}"
it=$(psq postgres "select count(*) from pg_stat_activity where state='idle in transaction'" 2>/dev/null)
check_eq "idle-in-transaction sessions" "0" "${it:-x}"
av=$(psq "$DB" "select coalesce(reloptions::text,'') like '%autovacuum_enabled=false%' from pg_class where oid='app.orders'::regclass" 2>/dev/null)
check_eq "autovacuum disabled on app.orders" "f" "$av"
d=$(psq "$DB" "select n_dead_tup <= greatest(n_live_tup/20, 100) from pg_stat_user_tables where relid='app.orders'::regclass" 2>/dev/null)
check_eq "app.orders dead tuples cleaned up" "t" "$d"
finish
