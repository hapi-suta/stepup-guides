#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/02-missing-index-critical
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-02
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
u=$(psq stepup_store "select count(*) from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=any(i.indkey) where i.indrelid='orders'::regclass and a.attname='order_id' and i.indisunique" 2>/dev/null)
if [[ -n "$u" && "$u" -ge 1 ]]; then ok "orders.order_id has a primary key or unique index"; else bad "orders.order_id has a primary key or unique index (got ${u:-<none>})"; fi
plan=$(psq stepup_store "explain select * from orders where order_id = 1" 2>/dev/null)
if grep -qE 'Index (Only )?Scan' <<<"$plan"; then ok "lookup by order_id uses an index scan"; else bad "lookup by order_id uses an index scan (got: $(head -1 <<<"$plan"))"; fi
c=$(psq stepup_store "select count(*) from orders" 2>/dev/null)
if [[ -n "$c" ]]; then ok "can query orders ($c rows)"; else bad "can query orders"; fi
finish
