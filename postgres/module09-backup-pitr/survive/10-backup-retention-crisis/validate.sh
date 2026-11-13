#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/10-backup-retention-crisis
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-10; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }

cd /
pbr() { sudo -u postgres pgbackrest "$@"; }

CONF=/etc/pgbackrest/pgbackrest.conf; BK=/opt/pgsql/backup/pgbackrest/backup/main
r=$(grep -E '^repo1-retention-full=' "$CONF" | head -1 | cut -d= -f2)
if [[ -n "$r" && "$r" -ge 2 ]]; then ok "repo1-retention-full is $r (>=2)"; else bad "repo1-retention-full is >=2 (got ${r:-<unset>})"; fi
bad_m=0; for m in "$BK"/*/backup.manifest; do [[ -f "$m" && "$(head -c1 "$m")" != "[" ]] && bad_m=$((bad_m+1)); done
check_eq "no backup manifest is corrupt" "0" "$bad_m"
info=$(sudo -u postgres pgbackrest --stanza=main info 2>&1)
if grep -q 'status: ok' <<<"$info" && grep -q 'full backup:' <<<"$info"; then ok "pgbackrest info shows status ok and a full backup"; else bad "pgbackrest info shows status ok and a full backup"; fi
if sudo -u postgres pgbackrest --stanza=main check >/dev/null 2>&1; then ok "pgbackrest check succeeds"; else bad "pgbackrest check succeeds"; fi
if ls /opt/pgsql/backup/basebackup-emergency/base.tar.gz >/dev/null 2>&1; then ok "emergency pg_basebackup exists"; else bad "emergency pg_basebackup exists (expected /opt/pgsql/backup/basebackup-emergency/base.tar.gz)"; fi
for db in stepup_store appdb blobdb; do
  f=/opt/pgsql/backup/dumps/$db.custom
  if [[ -s "$f" ]] && sudo -u postgres "$PGBIN/pg_restore" --list "$f" >/dev/null 2>&1; then ok "logical dump $db.custom is valid"; else bad "logical dump $db.custom is valid"; fi
done
finish
