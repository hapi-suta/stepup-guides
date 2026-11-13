#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/03-grafana-datasource-broken
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
check_eq "grafana-server is active" "active" "$(systemctl is-active grafana-server)"
u=$(curl -s -m 5 -u admin:admin http://localhost:3000/api/datasources 2>/dev/null | python3 -c 'import sys,json
try:
  print(next(d["url"] for d in json.load(sys.stdin) if d.get("type")=="prometheus"))
except Exception:
  pass' 2>/dev/null)
u=${u%/}
check_eq "Grafana Prometheus datasource URL" "http://localhost:9090" "$u"
finish
