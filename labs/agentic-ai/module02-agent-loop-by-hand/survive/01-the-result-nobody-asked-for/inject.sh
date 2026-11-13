#!/usr/bin/env bash
# DESC: Breaks the tool_use_id that agent.py sends back, so every tool-using run is rejected with HTTP 400
# =============================================================================
# SCENARIO 01 - The Result Nobody Asked For (Agentic AI, Module 02)
# Runs ON the ai-lab server as ec2-user. Saves a copy of agent.py, then changes
# one expression so tool results no longer quote the id the model sent.
# =============================================================================
set -euo pipefail

AGENT="$HOME/agentic-ai/agent.py"
STATE_FILE="$HOME/.chaos-agentic-m02-01.agent.py"

if [[ ! -f "$AGENT" ]]; then
  echo "ERROR: $AGENT not found. Finish Module 02 Build 03 first." >&2
  exit 1
fi
if ! grep -q '"tool_use_id": block.id,' "$AGENT"; then
  echo "ERROR: agent.py is not in its expected state; restore it before injecting." >&2
  exit 1
fi

cp -p "$AGENT" "$STATE_FILE"
sed -i 's/"tool_use_id": block.id,/"tool_use_id": "toolu_" + block.name,/' "$AGENT"

echo ""
echo "============================================================"
echo "  ALERT: the DBA agent crashes on every incident question"
echo "  It prints its first tool call, then stops with an error"
echo "  before any answer. A teammate 'tidied up' agent.py last"
echo "  night."
echo "============================================================"
echo ""
