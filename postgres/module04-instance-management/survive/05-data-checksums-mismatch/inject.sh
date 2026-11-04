#!/usr/bin/env bash
# SUTA survive scenario: module04-instance-management/05-data-checksums-mismatch
# inject.sh - breaks the lab (idempotent) and prints the alert the learner sees.
# Runs ON the lab node as root (sudo bash inject.sh). Self-contained: no lib, no student.env.
set -uo pipefail
PGBIN=/usr/pgsql-16/bin; PGDATA=/opt/pgsql/data; PGPORT=5432; PGLOG=/opt/pgsql/log
psq() { sudo -u postgres "$PGBIN/psql" -p "$PGPORT" -d "$1" -v ON_ERROR_STOP=1 -tAXqc "$2"; }
pg_up() { sudo -u postgres "$PGBIN/pg_isready" -q -p "$PGPORT"; }
wait_up() { for _ in $(seq 1 30); do pg_up && return 0; sleep 1; done; return 1; }
say() { printf '%s\n' "$*"; }
PASSED=0; FAILED=0
ok() { say "[PASS] $1"; PASSED=$((PASSED+1)); }
bad() { say "[FAIL] $1"; FAILED=$((FAILED+1)); }
check_eq() { local d="$1" e="$2" a="$3"; [[ "$a" == "$e" ]] && ok "$d" || bad "$d (expected $e, got ${a:-<empty>})"; }
finish() { say "RESULT: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]; }
STATE_DIR=/var/lib/suta-survive/module04-05; mkdir -p "$STATE_DIR"

CD=/opt/pgsql/data-checksum; CPORT=5437; MARK="$STATE_DIR/corrupted"
[[ -x "$PGBIN/initdb" ]] || { say "postgresql-16 is not installed"; exit 1; }
cpg() { sudo -u postgres "$PGBIN/pg_ctl" -D "$CD" "$@"; }
if [[ -f "$MARK" && -d "$CD" ]]; then
  sudo -u postgres "$PGBIN/pg_isready" -q -p "$CPORT" || cpg -o "-p $CPORT" -l "$CD/log/startup.log" -w start >/dev/null 2>&1
else
  [[ -e "$CD" ]] && { say "$CD already exists and was not created by this scenario; refusing to touch it"; exit 1; }
  pg_up || { systemctl start postgresql-16 >/dev/null 2>&1; wait_up || { say "main cluster would not start"; exit 1; }; }
  sudo -u postgres "$PGBIN/initdb" -D "$CD" --data-checksums -A trust >/dev/null 2>&1 || { say "initdb failed"; exit 1; }
  sudo -u postgres mkdir -p "$CD/log"
  cpg -o "-p $CPORT" -l "$CD/log/startup.log" -w start >/dev/null 2>&1 || { say "test cluster would not start"; exit 1; }
  cpsq() { sudo -u postgres "$PGBIN/psql" -p "$CPORT" -d postgres -v ON_ERROR_STOP=1 -tAXqc "$1"; }
  cpsq "CREATE TABLE corruption_test (id int, payload text); INSERT INTO corruption_test SELECT g, repeat(md5(g::text), 8) FROM generate_series(1,500) g; CHECKPOINT;" >/dev/null
  rel=$(cpsq "SELECT pg_relation_filepath('corruption_test')")
  cpg stop -m fast -w >/dev/null 2>&1
  printf 'CHECKSUM-CHAOS' | sudo -u postgres dd of="$CD/$rel" bs=1 seek=$((8192+4000)) conv=notrunc status=none
  cpg -o "-p $CPORT" -l "$CD/log/startup.log" -w start >/dev/null 2>&1
  touch "$MARK"
fi
say "main cluster 5432: $(sudo -u postgres "$PGBIN/pg_isready" -p "$PGPORT")"
say "test cluster $CPORT: $(sudo -u postgres "$PGBIN/pg_isready" -p "$CPORT")"
say ""
say 'ALERT: A test cluster (port 5437) has suspected'
say 'data corruption after a storage event.'
say 'Users report errors when querying certain tables.'
say 'The main cluster on port 5432 is unaffected.'
say ''
say 'Cluster data dir: /opt/pgsql/data-checksum'
say 'Cluster port: 5437'
exit 0
