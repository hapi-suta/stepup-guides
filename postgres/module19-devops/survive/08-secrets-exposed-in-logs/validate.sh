#!/usr/bin/env bash
# SUTA survive scenario: module19-devops/08-secrets-exposed-in-logs
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
LAB=/tmp/secrets-chaos; LOG=$LAB/ci-logs/build-2026-04-19.log
old=$(cat /var/lib/suta-survive/module19-08/leaked_verifier_md5 2>/dev/null)
now=$(psq postgres "select md5(rolpassword) from pg_authid where rolname='dbadmin'" 2>/dev/null)
if [[ -n "$old" && -n "$now" && "$old" != "$now" ]]; then ok "dbadmin password has been rotated"; else bad "dbadmin password has been rotated (still the leaked credential)"; fi
n=$(grep -c 'SuperSecret123\|wJalrXUtnFEMI' "$LOG" 2>/dev/null); n=${n:-0}
check_eq "credentials left in the CI log" "0" "$n"
if [[ -f "$LAB/db-ci.yml" ]]; then ok "workflow file exists"; else bad "workflow file exists"; fi
w=$(grep -c 'SuperSecret123\|wJalrXUtnFEMI\|echo "AWS Key' "$LAB/db-ci.yml" 2>/dev/null); w=${w:-1}
check_eq "hardcoded or echoed secrets in the workflow" "0" "$w"
finish
