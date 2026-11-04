#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/07-sequence-exhausted
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
STATE_DIR=/var/lib/suta-survive/module05-07; mkdir -p "$STATE_DIR"

DB=stepup_store
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "tickets table exists" "tickets" "$(psq "$DB" "SELECT to_regclass('public.tickets')" 2>/dev/null)"
check_eq "ticket_id column is bigint" "bigint" "$(psq "$DB" "SELECT data_type FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'ticket_id'" 2>/dev/null)"
check_eq "sequence is bigint" "bigint" "$(psq "$DB" "SELECT data_type FROM pg_sequences WHERE sequencename = 'tickets_ticket_id_seq'" 2>/dev/null)"
check_eq "sequence has room remaining" "t" "$(psq "$DB" "SELECT max_value - last_value > 1000000 FROM pg_sequences WHERE sequencename = 'tickets_ticket_id_seq'" 2>/dev/null)"
check_eq "ticket_id still takes its default from the sequence" "t" "$(psq "$DB" "SELECT pg_get_expr(adbin, adrelid) LIKE '%tickets_ticket_id_seq%' FROM pg_attrdef WHERE adrelid = 'public.tickets'::regclass AND adnum = (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.tickets'::regclass AND attname = 'ticket_id')" 2>/dev/null)"
finish
