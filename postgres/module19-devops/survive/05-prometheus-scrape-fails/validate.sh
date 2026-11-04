#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/05-prometheus-scrape-fails
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
U=/etc/systemd/system/postgres_exporter.service
if grep -qE 'WRONG_PASSWORD|nonexistent_db' "$U" 2>/dev/null; then bad "service DSN no longer has the wrong password or database"; else ok "service DSN no longer has the wrong password or database"; fi
check_eq "postgres_exporter service is active" "active" "$(systemctl is-active postgres_exporter)"
v=""; for _ in 1 2 3 4 5 6 7 8; do v=$(curl -s -m 3 http://localhost:9187/metrics | awk '/^pg_up /{print $2}'); [[ "$v" == "1" ]] && break; sleep 1; done
check_eq "exporter reports pg_up 1" "1" "$v"
finish
