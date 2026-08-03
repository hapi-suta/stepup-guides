#!/usr/bin/env bash
# SURVIVE validate: confirm the client now survives a flaky (429 + hang) API.
#
# PASS conditions:
#   1. The client source sets a request timeout (has timeout= on the call).
#   2. The client has a retry loop (handles 429 / retries).
#   3. Running the client against the flaky API succeeds within a bounded time
#      (proves it retries through 429s/timeouts and never hangs indefinitely).
#
# Run as ec2-user after following runbook.md. Requires the flaky API on :8300
# (inject.sh starts it); this script restarts it if needed.
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project1}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

PY=".venv/bin/python"
[ -x "$PY" ] || PY="python3.12"

[ -f fragile_client.py ] || fail "fragile_client.py not found - run inject.sh first"

# 1. Must set a timeout.
if ! grep -q "timeout" fragile_client.py; then
  fail "client sets no request timeout - it can hang forever"
fi
echo "OK: client sets a request timeout"

# 2. Must handle 429 / retry.
if ! grep -qE "429|retr|backoff|MAX_RETRIES" fragile_client.py; then
  fail "client has no retry/backoff logic - it will die on the first 429"
fi
echo "OK: client has retry/backoff logic"

# Make sure the flaky API is up.
if ! curl -s --max-time 3 "http://127.0.0.1:8300/data" >/dev/null 2>&1; then
  echo "INFO: flaky API not responding, (re)starting it on :8300..."
  pkill -f "flaky_api:app" 2>/dev/null || true
  sleep 1
  nohup .venv/bin/uvicorn flaky_api:app --host 127.0.0.1 --port 8300 > flaky_api.log 2>&1 &
  sleep 3
fi

# 3. Run the client a few times; it must succeed each time within a bounded
#    wall-clock (proves it retries through failures and never hangs open).
for run in 1 2 3; do
  START=$(date +%s)
  OUT="$("$PY" fragile_client.py 2>/dev/null | tail -n 1 || true)"
  END=$(date +%s)
  ELAPSED=$((END - START))
  if ! echo "$OUT" | grep -q "'ok': True"; then
    fail "run $run did not succeed (got: ${OUT:-<none>})"
  fi
  if [ "$ELAPSED" -gt 60 ]; then
    fail "run $run took ${ELAPSED}s (>60s) - client is not bounding its waits"
  fi
  echo "OK: run $run succeeded in ${ELAPSED}s"
done

echo "PASS: client survives 429s and timeouts against the flaky endpoint."
