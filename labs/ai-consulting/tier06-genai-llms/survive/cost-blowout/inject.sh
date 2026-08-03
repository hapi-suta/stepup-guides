#!/usr/bin/env bash
#
# SURVIVE: cost-blowout
# Injects a client that hammers a LOCAL mock LLM server in an unbounded loop with
# NO token counting, NO budget, and NO caching - so the (simulated) spend runs
# away with nothing to stop it.
#
# No real API and no API key are needed - the mock server reports token usage so
# we can test the cost-control LOGIC (token counting, budget enforcement, caching)
# for free.
#
# Run this on your lab server as ec2-user. It builds the working dir, a venv,
# writes a mock LLM server that returns token usage, and a spender that loops
# with no budget, then runs it so you SEE the spend blow up. Your job (see
# runbook.md) is to add token counting + a budget (and caching) that STOPS it.
#
set -euo pipefail

WORKDIR="${HOME}/survive-cost-blowout"
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

echo "==> Writing mock_server.py (local stand-in LLM that reports token usage)"
cat > "${WORKDIR}/mock_server.py" <<'PYEOF'
#!/usr/bin/env python3
"""Local mock LLM server that returns token usage so we can test cost control
with NO API key and NO real spend.

POST / with JSON {"prompt": "..."} -> returns
{"text": "...", "input_tokens": N, "output_tokens": M}.
Token counts are derived from the prompt length (~4 chars per token, Concepts 6.1)
so identical prompts cost the same each time (which makes caching worthwhile).
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8973


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            prompt = json.loads(raw).get("prompt", "")
        except Exception:
            prompt = ""
        input_tokens = max(1, len(prompt) // 4)
        output_tokens = 50  # pretend every answer is ~50 tokens
        body = json.dumps({
            "text": "mock answer",
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        }).encode()
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

echo "==> Writing spender.py (BROKEN: no budget, no token counting, no caching)"
cat > "${WORKDIR}/spender.py" <<'PYEOF'
#!/usr/bin/env python3
"""Processes a batch of tickets by calling the mock LLM once per ticket.

BUG (this is the SURVIVE scenario): it loops over a large batch (with MANY
duplicate prompts) and calls the model every single time with NO budget cap,
NO token accounting used to stop, and NO caching of repeated prompts. On a real
provider this is exactly how a runaway loop or a bad batch blows the monthly
bill. Your job (runbook.md) is to add cost controls that STOP the spend.

No real API / key - the mock server on PORT reports token usage.
"""
import json
import urllib.request

PORT = 8973
# Illustrative prices (USD per 1K tokens). Real prices: confirm per provider.
PRICE_IN = 0.005
PRICE_OUT = 0.025

# A batch with LOTS of duplicates - caching would eliminate most of the spend.
BASE_TICKETS = [
    "refund please",
    "cannot log in",
    "app crashes on startup",
]
BATCH = BASE_TICKETS * 500  # 1500 calls, but only 3 UNIQUE prompts


def call_model(prompt: str) -> dict:
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/",
        data=json.dumps({"prompt": prompt}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=3) as resp:
        return json.loads(resp.read())


def process_batch():
    total_cost = 0.0
    calls = 0
    for ticket in BATCH:
        # BUG: no budget check, no cache - every ticket hits the model.
        usage = call_model(ticket)
        cost = (usage["input_tokens"] / 1000.0) * PRICE_IN + \
               (usage["output_tokens"] / 1000.0) * PRICE_OUT
        total_cost += cost
        calls += 1
    # This SPEND line lets the validator see the runaway (huge) cost.
    print(f"SPEND calls={calls} cost_usd={total_cost:.4f} stopped_by_budget=false")


if __name__ == "__main__":
    process_batch()
PYEOF

echo "==> Starting the mock LLM server on 8973"
pkill -f "mock_server.py 8973" 2>/dev/null || true
sleep 1
nohup python "${WORKDIR}/mock_server.py" 8973 >/dev/null 2>&1 &
sleep 1

echo
echo "==> Running the broken spender.py so you can see the runaway spend:"
echo "-------------------------------------------------------------"
cd "${WORKDIR}"
python "${WORKDIR}/spender.py" || true
echo "-------------------------------------------------------------"
echo
echo "Notice: 1500 calls made and nothing stopped it - and only 3 prompts were"
echo "actually unique, so caching alone would have cut ~99.8% of the calls. No"
echo "budget means a runaway loop bills forever. Open runbook.md and add controls."
echo
echo "(Leaving the mock server running on 8973 for your fix + the validator.)"
