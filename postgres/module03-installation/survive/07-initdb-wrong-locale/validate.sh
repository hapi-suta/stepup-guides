#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/07-initdb-wrong-locale
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

PG15BIN=/usr/pgsql-15/bin
p15() { sudo -u postgres "$PG15BIN/psql" -p 5433 -d postgres -v ON_ERROR_STOP=1 -tAXqc "$1"; }
check_eq "postgresql-15 service is active" "active" "$(systemctl is-active postgresql-15)"
check_eq "PG15 lc_collate is en_US.UTF-8" "en_US.UTF-8" "$(p15 "SHOW lc_collate" 2>/dev/null)"
check_eq "PG15 lc_ctype is en_US.UTF-8" "en_US.UTF-8" "$(p15 "SHOW lc_ctype" 2>/dev/null)"
check_eq "PG15 server_encoding is UTF8" "UTF8" "$(p15 "SHOW server_encoding" 2>/dev/null)"
check_eq "PG15 listens on port 5433" "5433" "$(p15 "SHOW port" 2>/dev/null)"
finish
