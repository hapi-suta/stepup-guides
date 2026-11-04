#!/usr/bin/env bash
# SUTA survive scenario: module12-performance-tuning/05-index-corruption
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module12-05
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
check_eq "amcheck extension exists" "1" "$(psq stepup_store "select count(*) from pg_extension where extname='amcheck'" 2>/dev/null)"
if out=$(psq stepup_store "select bt_index_check('idx_chaos5_account_num')" 2>&1); then ok "bt_index_check passes on idx_chaos5_account_num"; else bad "bt_index_check passes on idx_chaos5_account_num ($(head -1 <<<"$out"))"; fi
if out=$(psq stepup_store "set enable_seqscan = off; select count(*) from chaos5_accounts where account_num = 'ACC-000001'" 2>&1); then check_eq "query using the index returns the correct result" "1" "$(tail -1 <<<"$out")"; else bad "query using the index returns the correct result ($(head -1 <<<"$out"))"; fi
if out=$(psq stepup_store "select count(*) from chaos5_accounts" 2>&1); then check_eq "no errors reading the table (5000 rows)" "5000" "$out"; else bad "no errors reading the table ($(head -1 <<<"$out"))"; fi
finish
