#!/usr/bin/env bash
# SUTA survive scenario: module13-upgrades/02-old-cluster-still-running
# validate.sh - exits 0 only when the scenario is resolved. Read-only. Runs ON the lab node as root.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
STATE_DIR=/var/lib/suta-survive/module13-02; mkdir -p "$STATE_DIR"
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf "%s\n" "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
P15=/usr/pgsql-15/bin; D15=/opt/pgsql/data15; D16=/opt/pgsql/data16
psq15() { sudo -u postgres "$P15/psql" -p 5433 -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
up15() { sudo -u postgres "$P15/pg_isready" -q -p 5433; }
start15() { up15 || sudo -u postgres "$P15/pg_ctl" -D "$D15" -l "$PGLOG/pg15.log" -w -t 30 start >/dev/null 2>&1; up15; }
stop15() { up15 && sudo -u postgres "$P15/pg_ctl" -D "$D15" stop -m fast -w -t 30 >/dev/null 2>&1; ! up15; }
need15() {
  if [[ ! -x "$P15/postgres" || ! -f "$D15/PG_VERSION" || ! -f "$D16/PG_VERSION" ]]; then
    say "PRECONDITION: finish Tutorial 2 (PG15 binaries, the PG15 cluster at $D15 and the initdb'd PG16 target at $D16) first"; exit 2
  fi
}
run_check() {
  local w rc; w=$(mktemp -d); chown postgres:postgres "$w"
  ( cd "$w" && sudo -u postgres "$PGBIN/pg_upgrade" --old-bindir=/usr/pgsql-15/bin --new-bindir="$PGBIN" \
      --old-datadir=/opt/pgsql/data15 --new-datadir=/opt/pgsql/data16 --check >"$w/out" 2>&1 ); rc=$?
  CHECK_OUT=$(cat "$w/out" 2>/dev/null); rm -rf "$w"; return $rc
}

if up15; then bad "PG15 cluster is stopped (still accepting connections on 5433)"; else ok "PG15 cluster is stopped"; fi
[[ -f "$D15/postmaster.pid" ]] && bad "no postmaster.pid left in $D15" || ok "no postmaster.pid left in $D15"
if sudo -u postgres "$PGBIN/pg_isready" -q -p 5434; then bad "PG16 target cluster is stopped"; else ok "PG16 target cluster is stopped"; fi
if ! up15 && run_check; then ok "pg_upgrade --check passes with both clusters stopped"; else bad "pg_upgrade --check passes with both clusters stopped (got: $(printf '%s' "${CHECK_OUT:-<no output>}" | grep -iE 'fatal|failure|postmaster|shutdown' | head -1))"; fi
if pg_up; then ok "PG16 production cluster is still running"; else bad "PG16 production cluster is still running"; fi
finish
