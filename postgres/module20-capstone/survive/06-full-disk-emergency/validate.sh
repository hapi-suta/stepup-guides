#!/usr/bin/env bash
# SUTA survive scenario: module20-capstone/06-full-disk-emergency
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
DB=appdb
for f in /tmp/filler_disk.dat /opt/pgsql/log/filler_1.dat /opt/pgsql/log/filler_2.dat /opt/pgsql/backup/filler_1.dat; do
  if [[ -e "$f" ]]; then bad "filler file removed: $f"; else ok "filler file removed: $f"; fi
done
check_eq "inactive replication slot leak_slot_capstone" "0" "$(psq postgres "select count(*) from pg_replication_slots where slot_name='leak_slot_capstone'" 2>/dev/null)"
check_eq "filler table app.disk_filler" "0" "$(psq "$DB" "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname='disk_filler'" 2>/dev/null)"
check_eq "filler customer rows" "0" "$(psq "$DB" "select count(*) from app.customers where email like 'diskfill%@capstone.lab'" 2>/dev/null)"
check_eq "server is a primary accepting writes (not in recovery)" "f" "$(psq postgres "select pg_is_in_recovery()" 2>/dev/null)"
pct=$(df -P /opt/pgsql | awk 'NR==2{gsub("%","",$5); print 100-$5}')
if [[ "${pct:-0}" -ge 15 ]]; then ok "/opt/pgsql filesystem has ${pct}% free"; else bad "/opt/pgsql filesystem has >= 15% free (got ${pct:-<empty>}%)"; fi
finish
