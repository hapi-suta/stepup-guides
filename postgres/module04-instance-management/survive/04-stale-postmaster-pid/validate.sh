#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/04-stale-postmaster-pid
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
STATE_DIR=/var/lib/suta-survive/module04-04; mkdir -p "$STATE_DIR"

PIDFILE="$PGDATA/postmaster.pid"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
pid=$(head -1 "$PIDFILE" 2>/dev/null)
main=$(systemctl show -p MainPID --value postgresql-16 2>/dev/null)
if [[ "$pid" =~ ^[0-9]+$ && "$pid" == "$main" ]]; then ok "postmaster.pid holds the running postmaster PID ($pid)"; else bad "postmaster.pid holds the running postmaster PID (expected ${main:-<none>}, got ${pid:-<none>})"; fi
if [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]]; then ok "postmaster.pid does not contain PID 1"; else bad "postmaster.pid does not contain PID 1 (got ${pid:-<none>})"; fi
comm=$(cat "/proc/${pid:-0}/comm" 2>/dev/null)
check_eq "that PID is a postgres process" "postgres" "$comm"
check_eq "PostgreSQL answers queries" "1" "$(psq labdb 'SELECT 1' 2>/dev/null)"
finish
