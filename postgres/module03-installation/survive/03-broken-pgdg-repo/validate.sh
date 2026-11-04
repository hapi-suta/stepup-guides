#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/03-broken-pgdg-repo
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

REPO=/etc/yum.repos.d/pgdg-redhat-all.repo
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if grep -q 'BROKEN' "$REPO" 2>/dev/null; then bad "PGDG repo has a valid baseurl (BROKEN still present)"; else ok "PGDG repo has a valid baseurl"; fi
if grep -E '^baseurl=' "$REPO" 2>/dev/null | grep -q '/pub/repos/yum/'; then ok "baseurl points at /pub/repos/yum/"; else bad "baseurl points at /pub/repos/yum/"; fi
if timeout 25 dnf -q repolist 2>/dev/null | grep -q '^pgdg16'; then ok "pgdg16 appears in dnf repolist"; else bad "pgdg16 appears in dnf repolist"; fi
if timeout 25 dnf -q info postgresql16-contrib >/dev/null 2>&1; then ok "dnf can query postgresql16 packages"; else bad "dnf can query postgresql16 packages"; fi
if [[ -e "$REPO.chaos-bak" ]]; then bad "backup repo file cleaned up ($REPO.chaos-bak)"; else ok "backup repo file cleaned up"; fi
finish
