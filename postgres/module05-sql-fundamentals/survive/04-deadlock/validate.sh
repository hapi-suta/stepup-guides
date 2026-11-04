#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/04-deadlock
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
STATE_DIR=/var/lib/suta-survive/module05-04; mkdir -p "$STATE_DIR"

DB=stepup_store
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "deadlock_accounts table exists" "deadlock_accounts" "$(psq "$DB" "SELECT to_regclass('public.deadlock_accounts')" 2>/dev/null)"
check_eq "total balance is 3000.00 (no money lost or created)" "3000.00" "$(psq "$DB" 'SELECT sum(balance) FROM deadlock_accounts' 2>/dev/null)"
if grep -qh 'deadlock detected' "$PGLOG"/postgresql-*.log 2>/dev/null; then ok "deadlock log entry exists"; else bad "deadlock log entry exists (none found in $PGLOG)"; fi
b=$(psq "$DB" "SELECT string_agg(balance::text, '/' ORDER BY id) FROM deadlock_accounts" 2>/dev/null)
if [[ -n "$b" && "$b" != "1000.00/2000.00" ]]; then ok "an ordered-lock transfer was applied (balances $b)"; else bad "an ordered-lock transfer was applied (balances still the seeded 1000.00/2000.00)"; fi
finish
