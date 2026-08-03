#!/usr/bin/env bash
# SURVIVE validate: confirm the app recovered from the broken DB connection.
#
# PASS conditions:
#   1. .env no longer contains the injected wrong password.
#   2. /health returns {"status":"ok"} (app can reach the database).
#   3. /summary returns a JSON body with a "total" (data path works).
#
# Run as ec2-user after following runbook.md.
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project1}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

# 1. The injected bad password must be gone from config.
if grep -q "WRONG-PASSWORD-INJECTED" .env 2>/dev/null; then
  fail ".env still contains the injected wrong password - config not fixed"
fi
echo "OK: injected bad password removed from .env"

# 2. Health check must be ok.
HEALTH="$(curl -s --max-time 5 http://127.0.0.1:8000/health || true)"
if ! echo "$HEALTH" | grep -q '"status":"ok"'; then
  fail "/health did not return ok (got: ${HEALTH:-<no response>}) - app not recovered"
fi
echo "OK: /health returns ok - database reachable"

# 3. Data endpoint must work.
SUMMARY="$(curl -s --max-time 5 http://127.0.0.1:8000/summary || true)"
if ! echo "$SUMMARY" | grep -q '"total"'; then
  fail "/summary did not return a total (got: ${SUMMARY:-<no response>})"
fi
echo "OK: /summary returns data"

echo "PASS: database connection recovered, app healthy."
