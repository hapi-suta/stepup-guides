#!/usr/bin/env bash
# validate.sh - Agentic AI Module 01, Scenario 01: The Call That Will Not Go Through
# Runs ON the ai-lab server as ec2-user. Checks side effects only, never the
# wording of an AI answer: the model line is exact again, the key file is still
# private, and a real call succeeds and is logged.
set -uo pipefail

ENV_FILE="$HOME/.suta-llm.env"
STATE_FILE="$HOME/.chaos-agentic-m01-01.state"
LOG="$HOME/agentic-ai/logs/calls.jsonl"
PASSED=0; FAILED=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; PASSED=$((PASSED+1)); else echo "  FAIL  $1"; FAILED=$((FAILED+1)); fi; }

echo "== Validating: The Call That Will Not Go Through =="
check "model line is exactly claude-haiku-5-5" "grep -qx 'export SUTA_LLM_MODEL=claude-haiku-5-5' '$ENV_FILE'"
check "key file is still mode 600" "[ \"\$(stat -c %a '$ENV_FILE')\" = 600 ]"

BEFORE=$(wc -l < "$LOG" 2>/dev/null || echo 0)
check "first_call.py exits 0 with the fixed settings" \
  "cd ~/agentic-ai && source '$ENV_FILE' && .venv/bin/python first_call.py"
AFTER=$(wc -l < "$LOG" 2>/dev/null || echo 0)
check "the successful call was logged" "[ $AFTER -gt $BEFORE ]"

if (( FAILED == 0 )); then
  rm -f "$STATE_FILE"
  echo "== RESOLVED: $PASSED passed =="
  exit 0
fi
echo "== NOT RESOLVED: $PASSED passed, $FAILED failed =="
exit 1
