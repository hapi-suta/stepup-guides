#!/usr/bin/env bash
#
# SURVIVE: rate-limit-429-storm
# Injects a client that fires many requests at a LOCAL mock LLM server which
# returns HTTP 429 (rate limited) whenever requests arrive too fast. The client
# has NO backoff and NO batching, so it fails immediately under the storm.
#
# No real API and no API key are needed - the mock server enforces a fake rate
# limit so we can test the resilience LOGIC (exponential backoff + batching)
# for free.
#
# Run this on your lab server as ec2-user. It builds the working dir, a venv,
# writes a rate-limiting mock server and a client with no backoff, then runs the
# client so you SEE it fail on 429s. Your job (see runbook.md) is to add
# exponential backoff (respecting Retry-After) and batching so it survives.
#
set -euo pipefail

WORKDIR="${HOME}/survive-rate-limit-429-storm"
VENV="${WORKDIR}/venv"

echo "==> Creating working directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Creating Python virtual environment (python3.12)"
if [[ ! -d "${VENV}" ]]; then
  python3.12 -m venv "${VENV}"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
python -m pip install --quiet --upgrade pip

echo "==> Writing mock_server.py (local LLM that returns 429 when hit too fast)"
cat > "${WORKDIR}/mock_server.py" <<'PYEOF'
#!/usr/bin/env python3
"""Local mock LLM server that enforces a fake rate limit, so we can test backoff
and batching with NO API key and NO real cost.

Rule: at most MAX_PER_WINDOW successful POSTs per WINDOW seconds. Requests over
that limit get HTTP 429 with a Retry-After header, just like a real provider.
"""
import json
import sys
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8974
WINDOW = 1.0          # seconds
MAX_PER_WINDOW = 5    # allow 5 successful calls per 1-second window

_recent = deque()     # timestamps of recent successful calls


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        _ = self.rfile.read(length)
        now = time.time()
        # Drop timestamps outside the window.
        while _recent and now - _recent[0] > WINDOW:
            _recent.popleft()

        if len(_recent) >= MAX_PER_WINDOW:
            # Too many, too fast -> 429 with a Retry-After hint.
            retry_after = max(0.0, WINDOW - (now - _recent[0]))
            body = json.dumps({"error": "rate_limited"}).encode()
            self.send_response(429)
            self.send_header("Content-Type", "application/json")
            self.send_header("Retry-After", f"{retry_after:.2f}")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        _recent.append(now)
        body = json.dumps({"text": "ok"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
PYEOF

echo "==> Writing client.py (BROKEN: no backoff, no batching)"
cat > "${WORKDIR}/client.py" <<'PYEOF'
#!/usr/bin/env python3
"""Sends a burst of requests to the mock LLM as fast as possible.

BUG (this is the SURVIVE scenario): it fires all requests back-to-back with NO
backoff and NO batching. The server's rate limit trips almost immediately and
the client crashes on the first 429 (HTTPError). Your job (runbook.md) is to add
exponential backoff (honoring Retry-After) and batching so ALL requests
eventually succeed.

No real API / key - the mock server on PORT enforces the rate limit.
"""
import json
import urllib.request

PORT = 8974
TOTAL_REQUESTS = 30


def call_model(prompt: str) -> dict:
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/",
        data=json.dumps({"prompt": prompt}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    # BUG: no retry / backoff. A 429 raises HTTPError and kills the run.
    with urllib.request.urlopen(req, timeout=3) as resp:
        return json.loads(resp.read())


def run():
    succeeded = 0
    for i in range(TOTAL_REQUESTS):
        call_model(f"request {i}")  # will blow up on the first 429
        succeeded += 1
    # This DONE line lets the validator confirm ALL requests succeeded.
    print(f"DONE succeeded={succeeded} total={TOTAL_REQUESTS}")


if __name__ == "__main__":
    run()
PYEOF

echo "==> Starting the rate-limiting mock server on 8974"
pkill -f "mock_server.py 8974" 2>/dev/null || true
sleep 1
nohup python "${WORKDIR}/mock_server.py" 8974 >/dev/null 2>&1 &
sleep 1

echo
echo "==> Running the broken client.py so you can see it fail under the 429 storm:"
echo "-------------------------------------------------------------"
cd "${WORKDIR}"
python "${WORKDIR}/client.py" || true
echo "-------------------------------------------------------------"
echo
echo "The client fired requests too fast, tripped the rate limit, and crashed on"
echo "a 429 (HTTP Error 429: Too Many Requests). No backoff and no batching means"
echo "a rate limit is fatal. Open runbook.md and add backoff + batching."
echo
echo "(Leaving the mock server running on 8974 for your fix + the validator.)"
