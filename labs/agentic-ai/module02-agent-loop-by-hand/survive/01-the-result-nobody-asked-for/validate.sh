#!/usr/bin/env bash
# validate.sh - Agentic AI Module 02, Scenario 01: The Result Nobody Asked For
# Runs ON the ai-lab server as ec2-user. Checks side effects only: the id line is
# correct again, a tool-using run finishes, a new tool call and a new run are logged.
set -uo pipefail

DIR="$HOME/agentic-ai"
STATE_FILE="$HOME/.chaos-agentic-m02-01.agent.py"
PASSED=0; FAILED=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; PASSED=$((PASSED+1)); else echo "  FAIL  $1"; FAILED=$((FAILED+1)); fi; }

echo "== Validating: The Result Nobody Asked For =="
check "tool results quote the model's id again" "grep -q '\"tool_use_id\": block.id,' '$DIR/agent.py'"
check "agent.py is valid Python" "cd '$DIR' && .venv/bin/python -m py_compile agent.py"

CALLS_BEFORE=$(wc -l < "$DIR/logs/tool_calls.jsonl" 2>/dev/null || echo 0)
RUNS_BEFORE=$(wc -l < "$DIR/logs/runs.jsonl" 2>/dev/null || echo 0)
check "a tool-using run finishes (exit 0)" \
  "cd '$DIR' && source ~/.suta-llm.env && timeout 120 .venv/bin/python agent.py 'How full is the root filesystem? Use the disk tool.'"
CALLS_AFTER=$(wc -l < "$DIR/logs/tool_calls.jsonl" 2>/dev/null || echo 0)
RUNS_AFTER=$(wc -l < "$DIR/logs/runs.jsonl" 2>/dev/null || echo 0)
check "the run made and logged at least one tool call" "[ $CALLS_AFTER -gt $CALLS_BEFORE ]"
check "the run was logged and ended with end_turn" \
  "[ $RUNS_AFTER -gt $RUNS_BEFORE ] && tail -1 '$DIR/logs/runs.jsonl' | grep -q '\"stop_reason\": \"end_turn\"'"

if (( FAILED == 0 )); then
  rm -f "$STATE_FILE"
  echo "== RESOLVED: $PASSED passed =="
  exit 0
fi
echo "== NOT RESOLVED: $PASSED passed, $FAILED failed =="
exit 1
