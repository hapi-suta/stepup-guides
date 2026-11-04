#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/07-tablespace-path-conflict
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-07; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

if pg_up; then ok "PostgreSQL is running"; else bad "PostgreSQL is running"; finish; exit 1; fi
oid=$(psq stepup_store "select oid from pg_tablespace where spcname='chaos7_tbs'" 2>/dev/null)
tgt=$(readlink -f "$PGDATA/pg_tblspc/$oid" 2>/dev/null)
if [[ -n "$oid" && -d "$tgt" ]]; then ok "tablespace symlink target exists ($tgt)"; else bad "tablespace symlink target exists (expected a directory, got ${tgt:-<none>})"; fi
n=$(psq stepup_store "select count(*) from chaos7_archive" 2>/dev/null)
if [[ -n "$n" ]]; then ok "chaos7_archive table is accessible"; else bad "chaos7_archive table is accessible (query failed)"; fi
check_eq "chaos7_archive returns 5000 rows" "5000" "${n:-}"
finish
