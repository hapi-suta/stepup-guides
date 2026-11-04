#!/usr/bin/env bash
# SUTA survive scenario: module15-advanced-monitoring/04-disk-full-metrics-loss
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
if [[ -e /var/lib/prometheus/_junk_fill ]]; then bad "junk fill file removed from /var/lib/prometheus"; else ok "junk fill file removed from /var/lib/prometheus"; fi
check_eq "prometheus service is active" "active" "$(systemctl is-active prometheus)"
check_eq "Prometheus is healthy" "Prometheus Server is Healthy." "$(curl -s -m 3 http://localhost:9090/-/healthy)"
finish
