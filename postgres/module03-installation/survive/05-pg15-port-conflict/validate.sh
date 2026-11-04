#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/05-pg15-port-conflict
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

PG15BIN=/usr/pgsql-15/bin; PG15DATA=/opt/pgsql/data15
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
check_eq "postgresql-15 service is active" "active" "$(systemctl is-active postgresql-15)"
check_eq "PG15 is configured for port 5433" "5433" "$(sudo -u postgres "$PG15BIN/postgres" -D "$PG15DATA" -C port 2>/dev/null)"
if sudo -u postgres "$PGBIN/pg_isready" -q -p 5432; then ok "PG16 accepts connections on 5432"; else bad "PG16 accepts connections on 5432"; fi
if sudo -u postgres "$PG15BIN/pg_isready" -q -p 5433; then ok "PG15 accepts connections on 5433"; else bad "PG15 accepts connections on 5433"; fi
finish
