#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/02-prometheus-scrape-failure
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
PY=/etc/prometheus/prometheus.yml
if awk '/job_name/{j=($0 ~ /postgres/)} j && /localhost:9999/{f=1} END{exit !f}' "$PY"; then bad "postgres job no longer targets the wrong port"; else ok "postgres job no longer targets the wrong port"; fi
if awk '/job_name/{j=($0 ~ /postgres/)} j && /:9187/{f=1} END{exit !f}' "$PY"; then ok "postgres job targets port 9187"; else bad "postgres job targets port 9187"; fi
h=""; for _ in $(seq 1 20); do
  h=$(curl -s -m 3 http://localhost:9090/api/v1/targets | python3 -c 'import sys,json
try:
  d=json.load(sys.stdin)
  print(",".join(t["health"] for t in d["data"]["activeTargets"] if t["labels"].get("job")=="postgres"))
except Exception:
  print("")' 2>/dev/null)
  [[ "$h" == "up" ]] && break; sleep 1; done
check_eq "Prometheus reports the postgres target up" "up" "$h"
finish
