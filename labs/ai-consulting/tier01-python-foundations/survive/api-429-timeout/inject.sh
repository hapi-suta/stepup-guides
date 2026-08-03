#!/usr/bin/env bash
# SURVIVE inject: make the API client hit 429s and timeouts against a flaky
# endpoint, using a client that has NO retry/backoff (so it fails).
#
# Simulates calling a rate-limited, occasionally-hanging external API (an LLM
# provider, a data source). A naive client with no timeout/retry either hangs
# forever or dies on the first 429.
#
# What this does:
#   1. Writes a flaky server (flaky_api.py) that returns 429 ~50% of the time
#      and hangs ~20% of the time.
#   2. Starts it in the background on port 8300.
#   3. Writes a NAIVE client (fragile_client.py) with no timeout and no retry.
#
# Run as ec2-user. Requires Project 1 in ~/project1 with the .venv from BUILD
# and the 'requests' package (pip install requests if missing).
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project1}"
cd "$PROJECT_DIR"

PY=".venv/bin/python"
[ -x "$PY" ] || PY="python3.12"

# Ensure requests + uvicorn/fastapi are present.
"$PY" -c "import requests" 2>/dev/null || .venv/bin/pip install -q requests==2.32.3 || true

echo "[inject] writing a flaky API server (429s + hangs)..."
cat > flaky_api.py <<'PY'
"""Flaky API: ~50% of calls return 429, ~20% hang for 8s."""
import random
import time

from fastapi import FastAPI, Response

app = FastAPI()


@app.get("/data")
def data(response: Response):
    roll = random.random()
    if roll < 0.50:
        response.status_code = 429
        response.headers["Retry-After"] = "1"
        return {"error": "rate limited"}
    if roll < 0.70:
        time.sleep(8)  # hang longer than any sane timeout
    return {"ok": True, "value": 42}
PY

echo "[inject] starting flaky API on port 8300..."
pkill -f "flaky_api:app" 2>/dev/null || true
sleep 1
nohup .venv/bin/uvicorn flaky_api:app --host 127.0.0.1 --port 8300 > flaky_api.log 2>&1 &
sleep 3

echo "[inject] writing a NAIVE client (no timeout, no retry)..."
cat > fragile_client.py <<'PY'
"""Naive client - no timeout, no retry. Fails on the flaky API. FIX ME."""
import requests

BASE_URL = "http://127.0.0.1:8300"


def fetch():
    resp = requests.get(f"{BASE_URL}/data")  # no timeout: can hang forever
    resp.raise_for_status()                  # no retry: dies on the first 429
    return resp.json()


if __name__ == "__main__":
    print(fetch())
PY

echo "[inject] DONE."
echo "[inject] Reproduce the failure with:"
echo "[inject]   cd ~/project1 && .venv/bin/python fragile_client.py"
echo "[inject] (Run it a few times: it will either hang ~8s or raise a 429.)"
echo "[inject] Then follow runbook.md to add timeout + backoff."
