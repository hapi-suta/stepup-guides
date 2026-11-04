#!/usr/bin/env bash
# SUTA survive scenario: module09-backup-pitr/05-pgbackrest-repo-corruption
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module09-05; mkdir -p "$STATE_DIR"
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

BK=/opt/pgsql/backup/pgbackrest/backup/main
L=$(cat /var/lib/suta-survive/module09-05/label 2>/dev/null)
if [[ -z "$L" ]]; then bad "inject state found (run inject.sh first)"; finish; exit 1; fi
[[ -d "$BK/$L" ]] && bad "corrupted backup set $L removed from the repo" || ok "corrupted backup set $L removed from the repo"
bad_m=0; for m in "$BK"/*/backup.manifest; do [[ -f "$m" && "$(head -c1 "$m")" != "[" ]] && bad_m=$((bad_m+1)); done
check_eq "no backup manifest is corrupt" "0" "$bad_m"
inj=$(stat -c %Y /var/lib/suta-survive/module09-05/label 2>/dev/null || echo 0)
newest=0; for s in $(sudo -u postgres pgbackrest --stanza=main info --output=json 2>/dev/null | grep -o '"stop":[0-9]*' | cut -d: -f2); do (( s > newest )) && newest=$s; done
if (( newest > inj )); then ok "a new backup exists (finished after the corruption)"; else bad "a new backup exists (expected a backup newer than the corruption)"; fi
if timeout 25 sudo -u postgres pgbackrest --stanza=main verify >/dev/null 2>&1; then ok "pgbackrest verify reports no errors"; else bad "pgbackrest verify reports no errors"; fi
if sudo -u postgres pgbackrest --stanza=main check >/dev/null 2>&1; then ok "pgbackrest check succeeds"; else bad "pgbackrest check succeeds"; fi
finish
