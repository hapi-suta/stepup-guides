#!/usr/bin/env bash
# SUTA survive scenario: module20-capstone/04-security-breach-response
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
DB=appdb; HBA="$PGDATA/pg_hba.conf"
check_eq "backdoor_admin role exists" "0" "$(psq postgres "select count(*) from pg_roles where rolname='backdoor_admin'" 2>/dev/null)"
check_eq "app_readwrite is superuser" "f" "$(psq postgres "select rolsuper from pg_roles where rolname='app_readwrite'" 2>/dev/null)"
check_eq "exfiltration function app.exfil_data() exists" "0" "$(psq "$DB" "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app' and p.proname='exfil_data'" 2>/dev/null)"
check_eq "active remote trust rules in pg_hba.conf" "0" "$(psq postgres "select count(*) from pg_hba_file_rules where type like 'host%' and auth_method='trust'" 2>/dev/null)"
l=$(psq postgres "select pg_conf_load_time() >= to_timestamp($(stat -c %Y "$HBA" 2>/dev/null || echo 0))" 2>/dev/null)
check_eq "pg_hba.conf change reloaded" "t" "$l"
check_eq "log_connections" "on" "$(psq postgres 'show log_connections' 2>/dev/null)"
check_eq "log_disconnections" "on" "$(psq postgres 'show log_disconnections' 2>/dev/null)"
ls=$(psq postgres 'show log_statement' 2>/dev/null)
if [[ "$ls" == "ddl" || "$ls" == "mod" || "$ls" == "all" ]]; then ok "log_statement restored ($ls)"; else bad "log_statement restored (expected ddl, mod or all, got ${ls:-<empty>})"; fi
B=/var/lib/suta-survive/module20-04/verifiers.before
now=$(psq postgres "select rolname||':'||md5(coalesce(rolpassword,'')) from pg_authid where rolname in ('app_owner','app_readwrite','app_readonly','replicator') order by 1" 2>/dev/null)
if [[ -s "$B" ]]; then
  same=$(comm -12 <(sort "$B") <(printf '%s\n' "$now" | sort) | wc -l | tr -d ' ')
  check_eq "credentials left un-rotated" "0" "$same"
else
  bad "credentials rotated (no baseline from inject.sh found)"
fi
finish
