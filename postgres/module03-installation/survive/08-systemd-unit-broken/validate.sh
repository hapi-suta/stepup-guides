#!/usr/bin/env bash
# SUTA survive scenario: module03-installation/08-systemd-unit-broken
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

OV=/etc/systemd/system/postgresql-16.service.d/override.conf
check_eq "postgresql-16 service is active" "active" "$(systemctl is-active postgresql-16)"
if pg_up; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL accepts connections"; fi
if grep -q 'data-WRONG' "$OV" 2>/dev/null; then bad "override.conf no longer points at data-WRONG"; else ok "override.conf no longer points at data-WRONG"; fi
ENVV=$(systemctl show -p Environment --value postgresql-16 2>/dev/null)
if [[ " $ENVV " == *" PGDATA=/opt/pgsql/data "* ]]; then ok "systemd loads PGDATA=/opt/pgsql/data"; else bad "systemd loads PGDATA=/opt/pgsql/data (got ${ENVV:-<empty>})"; fi
check_eq "systemd has no unit change waiting for daemon-reload" "no" "$(systemctl show -p NeedDaemonReload --value postgresql-16 2>/dev/null)"
if [[ -f /usr/lib/systemd/system/postgresql-16.service ]]; then ok "packaged unit file still present"; else bad "packaged unit file still present"; fi
check_eq "data_directory is /opt/pgsql/data" "/opt/pgsql/data" "$(psq labdb "SHOW data_directory" 2>/dev/null)"
finish
