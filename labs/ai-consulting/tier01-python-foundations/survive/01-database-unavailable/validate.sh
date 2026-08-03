#!/usr/bin/env bash
#
# SURVIVE validation: confirms the service has recovered.
# Passes only if PostgreSQL is running AND the API reports healthy.
#
# Run on the lab server as ec2-user.
set -uo pipefail

fail() { echo "[validate] FAIL: $*"; exit 1; }

echo "[validate] Checking PostgreSQL is active ..."
[ "$(systemctl is-active postgresql)" = "active" ] || fail "postgresql is not active"

echo "[validate] Checking API health endpoint ..."
code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/health || true)"
[ "$code" = "200" ] || fail "/health returned HTTP $code (expected 200)"

echo "[validate] Checking /summary returns tickets ..."
total="$(curl -s http://127.0.0.1:8000/summary | grep -o '"total":[0-9]*' | cut -d: -f2)"
[ -n "$total" ] && [ "$total" -gt 0 ] || fail "/summary did not return a positive total"

echo "[validate] PASS: database is up, API is healthy, summary total=$total"
