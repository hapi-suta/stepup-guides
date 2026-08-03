#!/usr/bin/env bash
# SURVIVE validate: prove the rate limit and budget cap hold under a flood.
#
# PASS conditions:
#   1. Under a flood, some requests are BLOCKED (rate limit and/or budget cap
#      returned a non-200), i.e. the flood does not sail through unlimited.
#   2. Final spend is bounded by the configured cap (does not run away).
#   3. A defense exists in the code (rate limit AND budget cap).
#   4. A single normal request still succeeds (limits do not break real use).
#
# Run as ec2-user after following runbook.md.
set -uo pipefail

LAB="${LAB:-$HOME/t11-cost-dos}"
PORT="${PORT:-8000}"
cd "$LAB" 2>/dev/null || { echo "FAIL: $LAB not found - run inject.sh first"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

# 3. Enforcement must exist in code (look for the actual controls, not comments:
#    HTTPException with 429 for rate limit and 402 for budget cap).
if ! grep -qE "status_code=429" app.py; then
  fail "no enforced rate limit (HTTPException 429) found in app.py"
fi
if ! grep -qE "status_code=402" app.py; then
  fail "no enforced budget cap (HTTPException 402) found in app.py"
fi
if ! grep -qE "MAX_CALLS|MAX_SPEND" app.py; then
  fail "no MAX_CALLS/MAX_SPEND limits found in app.py"
fi
echo "OK: enforced rate limit (429) and budget cap (402) are present in the code"

# Fresh server so the spend meter starts at zero.
pkill -f "app:app.*$PORT" 2>/dev/null || true
sleep 1
nohup .venv/bin/uvicorn app:app --host 127.0.0.1 --port "$PORT" > server.log 2>&1 &
sleep 4

curl -s --max-time 3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 \
  || fail "server not responding on :$PORT"

# 1 + 2. Run the flood; expect blocks and bounded spend.
OUT="$(BASE_URL="http://127.0.0.1:$PORT" N=200 .venv/bin/python flood.py 2>/dev/null)"
echo "INFO: flood result:"
echo "$OUT"

BLOCKED="$(echo "$OUT" | sed -n 's/.*blocked=\([0-9]*\).*/\1/p')"
[ -n "$BLOCKED" ] || fail "could not read blocked count from flood output"
if [ "$BLOCKED" -lt 1 ]; then
  fail "no requests were blocked - the flood was unlimited"
fi
echo "OK: the flood was throttled/capped ($BLOCKED requests blocked)"

SPEND="$(echo "$OUT" | sed -n "s/.*'usd': \([0-9.]*\).*/\1/p")"
[ -n "$SPEND" ] || fail "could not read final spend"
# Bounded means well under what 200 big unlimited calls would have cost.
if awk "BEGIN{exit !($SPEND < 1.0)}"; then
  echo "OK: spend is bounded (\$$SPEND, cap held)"
else
  fail "spend ran away (\$$SPEND) - budget cap did not hold"
fi

# 4. A single normal request still works after the flood window.
sleep 61  # let the per-minute rate window reset
NORM="$(curl -s --max-time 5 -X POST "http://127.0.0.1:$PORT/ask" \
        -H 'Content-Type: application/json' -d '{"question":"hi"}')"
if ! echo "$NORM" | grep -qi "answer"; then
  echo "INFO: normal request response: $NORM"
  fail "a normal request no longer works after limits were added"
fi
echo "OK: a normal request still succeeds"

echo "PASS: cost-exhaustion DoS is rate-limited and budget-capped."
