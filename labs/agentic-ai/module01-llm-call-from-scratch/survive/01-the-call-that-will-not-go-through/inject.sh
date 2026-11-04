#!/usr/bin/env bash
# DESC: Changes the course model name in ~/.suta-llm.env to a near-miss typo (claude-haiku-5.5)
# =============================================================================
# SCENARIO 01 - The Call That Will Not Go Through (Agentic AI, Module 01)
# Runs ON the ai-lab server as ec2-user. Saves the original model line, then
# writes a one-character typo into the model name. Every LLM call then fails.
# The key itself is never printed or changed.
# =============================================================================
set -euo pipefail

ENV_FILE="$HOME/.suta-llm.env"
STATE_FILE="$HOME/.chaos-agentic-m01-01.state"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Ask SutaAI to have your key issued first." >&2
  exit 1
fi
if ! grep -q '^export SUTA_LLM_MODEL=claude-haiku-5-5$' "$ENV_FILE"; then
  echo "ERROR: the model line is not in its expected state; restore it before injecting." >&2
  exit 1
fi

umask 077
grep '^export SUTA_LLM_MODEL=' "$ENV_FILE" > "$STATE_FILE"
sed -i 's/^export SUTA_LLM_MODEL=claude-haiku-5-5$/export SUTA_LLM_MODEL=claude-haiku-5.5/' "$ENV_FILE"

echo ""
echo "============================================================"
echo "  ALERT: every AI script on ai-lab is failing"
echo "  first_call.py, cost.py and chat.py all stop with an error."
echo "  Nothing in ~/agentic-ai was changed. Log out, log back in,"
echo "  then investigate."
echo "============================================================"
echo ""
