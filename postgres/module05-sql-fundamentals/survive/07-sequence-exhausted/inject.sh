#!/usr/bin/env bash
# SUTA survive scenario: module05-sql-fundamentals/07-sequence-exhausted
# inject.sh - breaks the lab (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres env PGOPTIONS='-c client_min_messages=warning' "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module05-07; mkdir -p "$STATE_DIR"

[[ -x "$PGBIN/postgres" ]] || { say "postgresql-16 is not installed"; exit 1; }
if ! pg_up; then systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "PostgreSQL would not start"; exit 1; }; fi
DB=stepup_store
cur=$(psq "$DB" "SELECT (SELECT data_type FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'ticket_id') || '/' || (SELECT last_value FROM pg_sequences WHERE sequencename = 'tickets_ticket_id_seq')" 2>/dev/null)
if [[ "$cur" != "integer/2147483647" ]]; then
  psq "$DB" "$(cat <<'SQL'
DROP TABLE IF EXISTS tickets CASCADE;
DROP SEQUENCE IF EXISTS tickets_ticket_id_seq;
CREATE SEQUENCE tickets_ticket_id_seq AS bigint;
CREATE TABLE tickets (ticket_id integer PRIMARY KEY DEFAULT nextval('tickets_ticket_id_seq'), subject text NOT NULL, created_at timestamptz DEFAULT now());
ALTER SEQUENCE tickets_ticket_id_seq OWNED BY tickets.ticket_id;
INSERT INTO tickets (subject) SELECT 'Ticket ' || g FROM generate_series(1, 7) g;
SELECT setval('tickets_ticket_id_seq', 2147483647);
SQL
)" >/dev/null || { say "seeding failed"; exit 1; }
fi
say "tickets rows: $(psq "$DB" 'SELECT count(*) FROM tickets')"
say ""
say 'ALERT: Application error - cannot create new tickets.'
say 'INSERT into tickets table is failing with:'
say 'ERROR: integer out of range'
say 'The support ticket system is completely down.'
exit 0
