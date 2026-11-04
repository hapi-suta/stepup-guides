#!/usr/bin/env bash
# SUTA survive scenario: module02-architecture/02-stale-pid-file
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

PIDF="$PGDATA/postmaster.pid"
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
FP=$(head -1 "$PIDF" 2>/dev/null)
if [[ "$FP" =~ ^[0-9]+$ ]]; then ok "postmaster.pid exists with a valid PID ($FP)"; else bad "postmaster.pid exists with a valid PID (got ${FP:-<none>})"; fi
CMD=$(ps -p "${FP:-0}" -o comm= 2>/dev/null)
if [[ "$CMD" == "postgres" || "$CMD" == "postmaster" ]]; then ok "PID in the file is a running postmaster ($CMD)"; else bad "PID in the file is a running postmaster (expected postgres, got ${CMD:-<none>})"; fi
MP=$(systemctl show -p MainPID --value postgresql-16 2>/dev/null)
check_eq "PID in the file matches the service main PID" "$MP" "$FP"
if [[ "$(psq labdb "SELECT 'PostgreSQL is back'" 2>/dev/null)" == "PostgreSQL is back" ]]; then ok "psql connection succeeds"; else bad "psql connection succeeds"; fi
finish
