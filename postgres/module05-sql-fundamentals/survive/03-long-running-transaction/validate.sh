#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/03-long-running-transaction
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module05-03; mkdir -p "$STATE_DIR"

DB=stepup_store
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "no sessions in idle in transaction state" "0" "$(psq "$DB" "SELECT count(*) FROM pg_stat_activity WHERE state LIKE 'idle in transaction%'" 2>/dev/null)"
t=$(psq "$DB" "SHOW idle_in_transaction_session_timeout" 2>/dev/null)
if [[ -n "$t" && "$t" != "0" ]]; then ok "idle_in_transaction_session_timeout is non-zero ($t)"; else bad "idle_in_transaction_session_timeout is non-zero (got ${t:-<none>})"; fi
hp=$(cat "$STATE_DIR/holder.pid" 2>/dev/null)
if [[ -n "$hp" ]] && kill -0 "$hp" 2>/dev/null; then bad "chaos holder process is gone (pid $hp still alive)"; else ok "chaos holder process is gone"; fi
finish
