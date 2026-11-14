#!/usr/bin/env bash
# validate.sh - AI Engineer Module 03, Scenario 01: The Log Line That Is Not a Log Line
# Runs ON the ai-lab server as ec2-user. Checks side effects only: the awkward lines
# are still in the log, your code reads past them, the strict parser is still strict,
# and your tests (including a new one) pass. On success the original log is restored.
set -uo pipefail

DIR="$HOME/agentic-ai"
LOG="$DIR/data/postgresql.log"
STATE_FILE="$HOME/.chaos-aieng-m03-01.postgresql.log"
PY="$DIR/.venv/bin/python"
PASSED=0; FAILED=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; PASSED=$((PASSED+1)); else echo "  FAIL  $1"; FAILED=$((FAILED+1)); fi; }

echo "== Validating: The Log Line That Is Not a Log Line =="
check "the log still has all 20 lines (nothing was deleted)" "[ \"\$(wc -l < '$LOG')\" -eq 20 ]"
check "the two continuation lines are still in the log" "[ \"\$(grep -c \$'^\t' '$LOG')\" -eq 2 ]"
check "load_log reads past them and returns 18 records" \
  "cd '$DIR' && $PY -c \"import sys; from logparse import load_log; sys.exit(len(load_log()) != 18)\""
check "the new records are counted (FATAL 6, STATEMENT 1)" \
  "cd '$DIR' && $PY -c \"import sys; from logparse import load_log, count_by_severity; c = count_by_severity(load_log()); sys.exit(c.get('FATAL') != 6 or c.get('STATEMENT') != 1)\""
check "severity_summary works again" \
  "cd '$DIR' && $PY -c \"import sys; from logparse import severity_summary; sys.exit('FATAL=6' not in severity_summary())\""
check "parse_line still rejects a line that is not a record" \
  "cd '$DIR' && $PY -c \"
import sys
from logparse import parse_line
try:
    parse_line('garbage')
except ValueError:
    sys.exit(0)
sys.exit(1)\""
check "all your tests pass" "cd '$DIR' && $PY -m pytest -q"
check "you added a test for this incident (13 or more tests)" \
  "[ \"\$(cat '$DIR'/tests/test_*.py | grep -c '^def test_')\" -ge 13 ]"

if (( FAILED == 0 )); then
  if [[ -f "$STATE_FILE" ]]; then
    mv "$STATE_FILE" "$LOG"
    echo "  (the original 15-line sample log has been put back)"
  fi
  echo "== RESOLVED: $PASSED passed =="
  exit 0
fi
echo "== NOT RESOLVED: $PASSED passed, $FAILED failed =="
exit 1
