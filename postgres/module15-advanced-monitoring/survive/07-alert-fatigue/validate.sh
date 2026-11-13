#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/07-alert-fatigue
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
R=/etc/prometheus/rules/postgres.yml
[[ -f "$R" ]] && ok "rules file exists" || bad "rules file exists"
n=$(grep -cE '^[[:space:]]*expr:.*(> 1|> 0\.001|< 0\.9999|>= 0)[[:space:]]*$' "$R" 2>/dev/null)
check_eq "absurd thresholds left in rules file" "0" "${n:-x}"
if grep -q 'suta-alert-fatigue' "$R" 2>/dev/null; then bad "chaos marker removed from rules file"; else ok "chaos marker removed from rules file"; fi
if /usr/local/bin/promtool check rules "$R" >/dev/null 2>&1; then ok "promtool check rules passes"; else bad "promtool check rules passes"; fi
w=$(grep -cE '^[[:space:]]*-[[:space:]]*alert:' "$R" 2>/dev/null)
if [[ "${w:-0}" -ge 3 ]]; then ok "rules file still defines alerts ($w)"; else bad "rules file still defines alerts (got ${w:-0})"; fi
finish
