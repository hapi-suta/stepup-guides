#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# SURVIVE scenario: cost-runaway
# Tier 10 - MLOps and LLMOps (ai-consulting track)
#
# What this injects:
#   An LLM app whose serving code has NO budget cap. A runaway client (a retry
#   loop gone wrong) hammers the API and logs thousands of billable calls to
#   llm_metrics.jsonl. The cost_alert.py monitor shows spend far over the daily
#   budget - this is the 2am cost blowout.
#
# Student goal (see runbook.md):
#   Confirm the blowout with the cost monitor, then add a budget guard to the
#   serving path (guarded_serve.py) that REFUSES calls once the daily budget is
#   spent, prove the guard holds under the same runaway load, and document it.
#   Everything runs offline (mock LLM, simulated cost).
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12. Fully self-contained.
# =============================================================================

WORKDIR="${HOME}/survive-cost-runaway"

echo "==> Creating working directory at ${WORKDIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Creating Python 3.12 virtual environment"
python3.12 -m venv .venv
# shellcheck disable=SC1091
source "${WORKDIR}/.venv/bin/activate"
python -m pip install --quiet --upgrade pip

echo "==> Writing llm_client.py (offline mock)"
cat > llm_client.py <<'PYEOF'
"""Offline mock LLM. Returns a fixed answer; no network or key needed."""
import os


def complete(prompt, system=""):
    if not os.environ.get("LLM_API_KEY", "").strip():
        return "This is a support answer that costs tokens to produce."
    return "This is a support answer that costs tokens to produce."
PYEOF

echo "==> Writing serve_call.py (the UNGUARDED serving path - logs cost per call)"
cat > serve_call.py <<'PYEOF'
"""Unguarded LLM serving path. Every call is billed and logged. No budget cap.

This is the vulnerable code: it will happily serve forever, no matter the spend.
Usage: python serve_call.py "<question>"
"""
import json
import sys
from datetime import datetime, timezone

from llm_client import complete

LOG = "llm_metrics.jsonl"
PRICE_PER_1K_INPUT = 0.003
PRICE_PER_1K_OUTPUT = 0.015


def count_tokens(text):
    return max(1, len(text) // 4)


def serve(question):
    answer = complete(question)
    in_tok = count_tokens(question)
    out_tok = count_tokens(answer)
    cost = round(in_tok / 1000 * PRICE_PER_1K_INPUT
                 + out_tok / 1000 * PRICE_PER_1K_OUTPUT, 6)
    with open(LOG, "a") as fh:
        fh.write(json.dumps({
            "ts": datetime.now(timezone.utc).isoformat(),
            "input_tokens": in_tok, "output_tokens": out_tok,
            "cost_usd": cost, "error": False,
        }) + "\n")
    return answer


if __name__ == "__main__":
    q = sys.argv[1] if len(sys.argv) > 1 else "help"
    print(serve(q))
PYEOF

echo "==> Writing cost_alert.py (the cost/usage monitor)"
cat > cost_alert.py <<'PYEOF'
"""Cost monitor. Alerts (exit 1) if total spend exceeds the daily budget.

Usage: python cost_alert.py [--budget 1.00]
"""
import argparse
import json
from pathlib import Path

LOG = "llm_metrics.jsonl"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--budget", type=float, default=1.00)
    args = ap.parse_args()
    path = Path(LOG)
    if not path.exists():
        print("no llm_metrics.jsonl yet")
        return 1
    total_cost = 0.0
    requests = 0
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        total_cost += rec.get("cost_usd", 0.0)
        requests += 1
    total_cost = round(total_cost, 4)
    print(f"requests:   {requests}")
    print(f"total_cost: ${total_cost}")
    print(f"budget:     ${args.budget}")
    if total_cost > args.budget:
        print(f"ALERT: cost ${total_cost} exceeds daily budget ${args.budget}")
        print("RESULT: BUDGET BREACHED")
        return 1
    print("RESULT: within budget")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PYEOF

echo "==> Writing runaway.py (simulates the retry loop hammering the API)"
cat > runaway.py <<'PYEOF'
"""Simulate a runaway client: call the serving path many times in a loop.

Usage: python runaway.py <serving_module> <count>
  serving_module: 'serve_call' (unguarded) or 'guarded_serve' (student's fix)
"""
import importlib
import sys


def main():
    module_name = sys.argv[1] if len(sys.argv) > 1 else "serve_call"
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    mod = importlib.import_module(module_name)
    served = 0
    refused = 0
    for _ in range(count):
        try:
            result = mod.serve("please help me with my account " * 20)
            if result is None or (isinstance(result, str) and "BUDGET" in result):
                refused += 1
            else:
                served += 1
        except Exception:
            refused += 1
    print(f"attempted: {count}  served: {served}  refused: {refused}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PYEOF

echo "==> Unleashing the runaway loop against the UNGUARDED path (5000 calls)"
python runaway.py serve_call 5000

echo "==> Running the cost monitor so you can see the blowout (budget \$1.00/day)"
echo "-----------------------------------------------------------------"
python cost_alert.py --budget 1.00 || true
echo "-----------------------------------------------------------------"

cat <<EOF

==> Injection complete.

A runaway retry loop hammered the UNGUARDED serving path 5000 times. The cost
monitor shows spend far over the \$1.00 daily budget - this is the 2am cost
blowout. Nothing stopped it because serve_call.py has no budget cap.

Working directory: ${WORKDIR}
Files:
  llm_client.py   - offline mock; do not edit
  serve_call.py   - the UNGUARDED serving path (the vulnerable code); do not edit
  cost_alert.py   - the cost monitor; do not edit
  runaway.py      - the runaway loop simulator; do not edit
  llm_metrics.jsonl - the billed calls (grew huge)

Now follow runbook.md to add a budget guard (guarded_serve.py) that refuses
calls once the daily budget is spent, prove it holds under the same load, and
document the finding.
Reference: Concepts 10.3 (cost control) and 10.5 (threshold alerts).
EOF
