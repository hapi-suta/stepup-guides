#!/usr/bin/env bash
# SURVIVE inject: the agent attempts an IRREVERSIBLE action without approval.
#
# The failure: the model decides to run an irreversible operation (drop a table).
# In the "before" state the harness auto-approves action tools, so there is no
# human gate - the irreversible action executes and the data is gone. The human-
# approval gate must be the thing that stops it.
#
# What this does:
#   - Writes a self-contained scenario (scenario.py). policy.json controls
#     whether action tools require human approval. BEFORE: auto-approve ->
#     irreversible action runs. AFTER: require approval (denied by default for an
#     unexpected irreversible action) -> blocked.
#   - Everything runs on a MOCK model - no API key.
#
# Run on the lab server (CentOS Stream 9), as ec2-user, from this directory:
#   bash inject.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "[inject] writing the scenario with action tools AUTO-APPROVED (no gate)..."

cat > scenario.py <<'PY'
"""Self-contained irreversible-action scenario. Mock model, stdlib only.

policy.json:
  REQUIRE_APPROVAL - if False, action tools run automatically (no human gate).
                     if True, an action tool pauses for a human. In this non-
                     interactive scenario the "human" DENIES an unexpected
                     irreversible action (the fix).

The mock model decides to drop a table (an irreversible action). Whether that
runs depends entirely on the approval gate.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
POLICY_FILE = os.path.join(HERE, "policy.json")

# A "database" whose table proves whether the irreversible action ran.
DB = {"tables": ["users", "orders", "audit_log"]}

ACTION_TOOLS = {"drop_table"}   # irreversible

def tool_get_db_health(instance):
    return {"cpu_pct": 90, "instance": instance}

def tool_drop_table(table):
    # Irreversible: once dropped, it is gone.
    if table in DB["tables"]:
        DB["tables"].remove(table)
    return f"dropped {table}"

TOOLS = {"get_db_health": tool_get_db_health, "drop_table": tool_drop_table}

def human_gate(name, tool_input):
    """The human-approval gate. Non-interactive: a human reviewing an UNEXPECTED
    irreversible 'drop_table' denies it. (A real gate would prompt a person.)"""
    if name == "drop_table":
        return False   # human refuses an irreversible action they did not ask for
    return True

def mock_model(goal, transcript):
    if not transcript:
        return {"type": "tool_use", "name": "get_db_health", "input": {"instance": "pg-prod-1"}}
    # The model over-reaches: it decides to "clean up" by dropping a table.
    if not any(t.get("tool") == "drop_table" for t in transcript):
        return {"type": "tool_use", "name": "drop_table", "input": {"table": "audit_log"}}
    return {"type": "final", "text": "done"}

def run(goal):
    with open(POLICY_FILE) as fh:
        policy = json.load(fh)
    require_approval = policy["REQUIRE_APPROVAL"]
    transcript, audit = [], []
    for _ in range(10):
        step = mock_model(goal, transcript)
        if step["type"] == "final":
            audit.append({"event": "final"})
            break
        name = step["name"]
        tool_input = step.get("input", {})
        if name in ACTION_TOOLS:
            if require_approval:
                if not human_gate(name, tool_input):
                    audit.append({"event": "action_denied", "name": name, "input": tool_input})
                    transcript.append({"tool": name, "is_error": True, "result": "DENIED by human"})
                    continue
                audit.append({"event": "action_approved", "name": name, "input": tool_input})
            else:
                # BEFORE: no gate - action tools auto-approved.
                audit.append({"event": "action_auto_approved", "name": name, "input": tool_input})
        result = TOOLS[name](**tool_input)
        audit.append({"event": "tool_call", "name": name})
        transcript.append({"tool": name, "is_error": False, "result": result})
    return {"tables": DB["tables"], "audit": audit}

if __name__ == "__main__":
    print(json.dumps(run("Investigate pg-prod-1.")))
PY

# BEFORE state: no approval gate.
cat > policy.json <<'JSON'
{"REQUIRE_APPROVAL": false}
JSON

echo "[inject] running the agent (action tools auto-approved)..."
python3 scenario.py > last_run.json
echo "[inject] result: $(cat last_run.json)"
echo "[inject] DONE. The agent dropped a table with no human approval. Fix the"
echo "[inject]       policy per runbook.md, then run validate.sh."
