#!/usr/bin/env bash
#
# SURVIVE: region-outage
# A client app calls a PRIMARY cloud region (mock AWS us-east-1 on port 8991)
# which is DOWN (never started / connection refused). A SECONDARY cloud region
# (mock GCP europe-west1 on port 8992) IS healthy, but the app has NO failover,
# so a regional outage takes the whole feature offline.
#
# No real cloud / credentials needed - both "regions" are LOCAL mock servers, so
# you test the failover LOGIC (fail over to the second cloud) for free.
#
# Run on your lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-region-outage"
echo "==> Creating working directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Writing region_server.py (a local stand-in for a cloud AI region)"
cat > region_server.py <<'PYEOF'
#!/usr/bin/env python3
"""Tiny local mock of a cloud AI region. No key, no cost.
Usage: python3 region_server.py <port> <label>
Responds to POST / with {"region": "<label>", "text": "..."}."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
LABEL = sys.argv[2] if len(sys.argv) > 2 else "region"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        _ = self.rfile.read(length)
        body = json.dumps({"region": LABEL, "text": "ok from " + LABEL}).encode()
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

echo "==> Writing client.py (BROKEN: primary region only, NO failover)"
cat > client.py <<'PYEOF'
#!/usr/bin/env python3
"""Client that calls the PRIMARY cloud region only.

BUG (this is the SURVIVE scenario): no failover to the secondary cloud region.
When the primary region has an outage, every call fails and the feature is dead.
Your job (runbook.md) is to fail over to the SECONDARY region.

Both regions are local mock servers - no real cloud / key involved.
"""
import json
import urllib.request

PRIMARY_PORT = 8991    # mock AWS us-east-1 - inject.sh leaves this DOWN
SECONDARY_PORT = 8992  # mock GCP europe-west1 - healthy, but client ignores it


def call_region(port, prompt):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/",
        data=json.dumps({"prompt": prompt}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=3) as resp:
        return json.loads(resp.read())


def serve(prompt):
    # BUG: only ever calls the primary region. No failover.
    return call_region(PRIMARY_PORT, prompt)


if __name__ == "__main__":
    result = serve("Classify this ticket")
    print("RESULT " + json.dumps(result))
PYEOF

echo "==> Starting ONLY the SECONDARY region (8992). PRIMARY (8991) stays DOWN."
pkill -f "region_server.py 8991" 2>/dev/null || true
pkill -f "region_server.py 8992" 2>/dev/null || true
sleep 1
nohup python3 "${WORKDIR}/region_server.py" 8992 gcp-europe-west1 >/dev/null 2>&1 &
sleep 1

echo
echo "==> Running the broken client.py so you can see the outage failure:"
echo "-------------------------------------------------------------"
python3 "${WORKDIR}/client.py" || true
echo "-------------------------------------------------------------"
echo
echo "The primary region (8991) is down and the client has no failover, so the"
echo "feature is offline. Open runbook.md and add failover to the second cloud."
