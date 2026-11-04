#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/11-stale-stats-after-bulk-delete
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-11
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
st=$(psq stepup_store "select reltuples::bigint from pg_class where oid=to_regclass('support_tickets')" 2>/dev/null)
if [[ -n "$st" && "$st" -gt 1000 ]]; then ok "support_tickets reltuples > 1000 ($st)"; else bad "support_tickets reltuples > 1000 (got ${st:-<none>})"; fi
od=$(psq stepup_store "select reltuples::bigint from pg_class where oid='orders'::regclass" 2>/dev/null)
if [[ -n "$od" && "$od" -ge 0 ]]; then ok "orders has been analyzed (reltuples $od)"; else bad "orders has been analyzed (reltuples ${od:-<none>})"; fi
plan=$(psq stepup_store "explain select * from support_tickets where customer_id = 12345" 2>/dev/null)
if grep -qE 'Index (Only )?Scan|Bitmap' <<<"$plan"; then ok "support_tickets customer lookup uses an index"; else bad "support_tickets customer lookup uses an index (got: $(head -1 <<<"$plan"))"; fi
ps=$(psq stepup_store "select count(*) from pg_statistic where starelid=to_regclass('support_tickets')" 2>/dev/null)
if [[ -n "$ps" && "$ps" -ge 1 ]]; then ok "pg_statistic has entries for support_tickets ($ps)"; else bad "pg_statistic has entries for support_tickets (got ${ps:-<none>})"; fi
ro=$(psq stepup_store "select coalesce(reloptions::text,'') from pg_class where oid=to_regclass('support_tickets')" 2>/dev/null)
if [[ "$ro" == *autovacuum_enabled=false* ]]; then bad "autovacuum is re-enabled on support_tickets (reloptions $ro)"; else ok "autovacuum is re-enabled on support_tickets"; fi
finish
