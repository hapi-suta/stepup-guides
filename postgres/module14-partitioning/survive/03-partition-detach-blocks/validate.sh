#!/usr/bin/env bash
# SUTA survive scenario: module14-partitioning/03-partition-detach-blocks
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module14-03
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
check_eq "no ACCESS EXCLUSIVE lock held on orders_chaos3" "0" "$(psq stepup_store "select count(*) from pg_locks l join pg_class c on c.oid=l.relation where c.relname='orders_chaos3' and l.mode='AccessExclusiveLock' and l.granted" 2>/dev/null)"
out=$(sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d stepup_store -tAXq -v ON_ERROR_STOP=1 -c "SET lock_timeout = '3s'" -c "SELECT count(*) FROM orders_chaos3" 2>&1)
if [[ "$out" =~ ^[0-9]+$ ]]; then ok "orders_chaos3 accepts SELECT queries ($out rows)"; else bad "orders_chaos3 accepts SELECT queries (got: $(head -1 <<<"$out"))"; fi
check_eq "orders_chaos3_2024_01 is detached from the parent" "0" "$(psq stepup_store "select count(*) from pg_inherits where inhparent='orders_chaos3'::regclass and inhrelid=to_regclass('orders_chaos3_2024_01')" 2>/dev/null)"
finish
