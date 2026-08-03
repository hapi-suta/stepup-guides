#!/usr/bin/env bash
# SURVIVE inject: an agent stuck in an INFINITE tool-call loop burns budget.
#
# The failure: a confused model keeps calling the same read-only tool forever,
# never producing a final answer. With no termination conditions, the loop runs
# without end - every iteration costs tokens (money). This is a classic runaway
# agent: not malicious, just unbounded.
#
# What this does:
#   - Writes a self-contained scenario (scenario.py) whose loop limits are set so
#     high they never fire (the "before" state). The looping mock model then runs
#     until a hard safety stop we impose only to keep the demo from truly hanging.
#   - Everything runs on a MOCK model - no API key.
#
# Run on the lab server (CentOS Stream 9), as ec2-user, from this directory:
#   bash inject.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "[inject] writing the scenario with limits set effectively OFF (runaway state)..."

cat > scenario.py <<'PY'
"""Self-contained infinite-loop scenario. Mock model, stdlib only.

Limits come from limits.json:
  MAX_TOOL_CALLS - hard cap on tool calls per run (termination condition)
  MAX_TOKENS     - token budget per run (spending limit)

BEFORE (runaway): both set absurdly high -> the loop effectively never stops.
AFTER  (fixed):   sane values           -> the loop stops and reports it.

A HARD_SAFETY_STOP keeps the demo from literally hanging your terminal; if the
run hits it, that means your real limits never fired - i.e. still runaway.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIMITS_FILE = os.path.join(HERE, "limits.json")
HARD_SAFETY_STOP = 100000   # only to keep the demo terminable; NOT your real limit

def load_limits():
    with open(LIMITS_FILE) as fh:
        return json.load(fh)

def tool_get_db_health(instance):
    return {"cpu_pct": 30, "instance": instance}

TOOLS = {"get_db_health": tool_get_db_health}

def looping_mock_model(goal, transcript):
    # A confused model: always asks for the same tool, never finalizes.
    return {"type": "tool_use", "name": "get_db_health", "input": {"instance": "pg-prod-1"}}

def estimate_tokens(step):
    return max(1, len(json.dumps(step)) // 4)

def run(goal):
    limits = load_limits()
    max_calls = int(limits["MAX_TOOL_CALLS"])
    max_tokens = int(limits["MAX_TOKENS"])
    transcript = []
    tool_calls = 0
    tokens_used = 0
    stopped = None
    while True:
        # Termination checks BEFORE each step (this is the fix when limits are sane).
        if tool_calls >= max_calls:
            stopped = "max_tool_calls"; break
        if tokens_used >= max_tokens:
            stopped = "budget_exhausted"; break
        if tool_calls >= HARD_SAFETY_STOP:
            stopped = "hard_safety_stop"; break   # limits never fired -> still runaway
        step = looping_mock_model(goal, transcript)
        tokens_used += estimate_tokens(step)
        if step["type"] == "final":
            stopped = "model_done"; break
        TOOLS[step["name"]](**step.get("input", {}))
        tool_calls += 1
        transcript.append({"tool": step["name"]})
    return {"stopped": stopped, "tool_calls": tool_calls, "tokens_used": tokens_used,
            "limits": {"MAX_TOOL_CALLS": max_calls, "MAX_TOKENS": max_tokens}}

if __name__ == "__main__":
    print(json.dumps(run("Check the database.")))
PY

# BEFORE state: limits effectively off.
cat > limits.json <<'JSON'
{"MAX_TOOL_CALLS": 100000000, "MAX_TOKENS": 100000000}
JSON

echo "[inject] running the looping agent (limits OFF)..."
python3 scenario.py > last_run.json
echo "[inject] result: $(cat last_run.json)"
echo "[inject] DONE. The agent looped until the demo's HARD safety stop (your real"
echo "[inject]       limits never fired). Fix the limits per runbook.md, then run validate.sh."
