#!/usr/bin/env bash
#
# SURVIVE: provider-outage
# Injects a client app that calls a PRIMARY local mock LLM server which is DOWN
# (the process is never started / refuses connections), and has NO fallback. So
# every request fails and the feature is dead.
#
# No real API and no API key are needed - everything runs against a LOCAL mock
# LLM server so the resilience LOGIC (graceful degradation to a second provider)
# is what gets tested, for free.
#
# Run this on your lab server as ec2-user. It builds the working dir, a venv,
# writes a mock LLM server, a SECONDARY (backup) mock server, and a client with
# NO fallback, then runs the client so you SEE it fail. Your job (see runbook.md)
# is to add fallback so the app degrades gracefully to the backup provider.
#
set -euo pipefail

WORKDIR="${HOME}/survive-provider-outage"
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

echo "==> Writing mock_server.py (a local stand-in LLM - no key, no cost)"
cat > "${WORKDIR}/mock_server.py" <<'PYEOF'
#!/usr/bin/env python3
"""A tiny local mock LLM server. Stands in for a real provider so we can test
resilience logic with NO API key and NO cost.

Usage: python mock_server.py <port> <label>
Responds to POST / with a JSON body like {"provider": "<label>", "text": "..."}.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
LABEL = sys.argv[2] if len(sys.argv) > 2 else "mock"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        _ = self.rfile.read(length)  # ignore the prompt body for the mock
        body = json.dumps({"provider": LABEL, "text": "ok from " + LABEL}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # keep the lab output clean


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
PYEOF

echo "==> Writing client.py (BROKEN: primary is down, NO fallback)"
cat > "${WORKDIR}/client.py" <<'PYEOF'
#!/usr/bin/env python3
"""Client that calls the PRIMARY provider only. When primary is down, it dies.

BUG (this is the SURVIVE scenario): there is no fallback. The primary mock
server on PRIMARY_PORT is intentionally NOT running, so every call fails and
the feature is unavailable. Your job (runbook.md) is to add graceful
degradation to the SECONDARY provider.

No real API / key involved - both providers are local mock servers.
"""
import json
import urllib.request

PRIMARY_PORT = 8971    # intentionally NOT started by inject.sh -> connection refused
SECONDARY_PORT = 8972  # a backup mock server IS running, but the client ignores it


def call_provider(port: int, prompt: str) -> dict:
    """POST the prompt to a local mock provider and return its JSON response."""
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/",
        data=json.dumps({"prompt": prompt}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=3) as resp:
        return json.loads(resp.read())


def triage(prompt: str) -> dict:
    # BUG: only ever calls the primary. No try/except, no fallback.
    return call_provider(PRIMARY_PORT, prompt)


if __name__ == "__main__":
    result = triage("Classify this ticket")
    # This line prints RESULT so the validator can confirm success after the fix.
    print("RESULT " + json.dumps(result))
PYEOF

echo "==> Starting ONLY the SECONDARY (backup) mock server on 8972"
echo "    (the PRIMARY on 8971 is deliberately left DOWN)"
# Kill any stragglers from a previous run.
pkill -f "mock_server.py 8971" 2>/dev/null || true
pkill -f "mock_server.py 8972" 2>/dev/null || true
sleep 1
nohup python "${WORKDIR}/mock_server.py" 8972 secondary >/dev/null 2>&1 &
sleep 1

echo
echo "==> Running the broken client.py so you can see the failure:"
echo "-------------------------------------------------------------"
cd "${WORKDIR}"
python "${WORKDIR}/client.py" || true
echo "-------------------------------------------------------------"
echo
echo "The client tried the PRIMARY provider (8971), which is down, and gave up -"
echo "it never tried the healthy backup on 8972. That single point of failure is"
echo "the outage. Open runbook.md and add graceful fallback."
