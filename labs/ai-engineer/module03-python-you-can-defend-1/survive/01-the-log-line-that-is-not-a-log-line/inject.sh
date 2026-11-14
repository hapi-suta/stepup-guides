#!/usr/bin/env bash
# DESC: Appends real-world PostgreSQL log lines (a multi-line STATEMENT) so the log tools crash on lines that are not records
# =============================================================================
# SCENARIO 01 - The Log Line That Is Not a Log Line (AI Engineer, Module 03)
# Runs ON the ai-lab server as ec2-user. Saves a copy of the sample log, then
# appends five lines: three normal records and two continuation lines.
# Your code is not touched. Only the data changes.
# =============================================================================
set -euo pipefail

LOG="$HOME/agentic-ai/data/postgresql.log"
STATE_FILE="$HOME/.chaos-aieng-m03-01.postgresql.log"

if [[ ! -f "$LOG" ]]; then
  echo "ERROR: $LOG not found. Finish Module 02 Build 01 first." >&2
  exit 1
fi
if [[ "$(wc -l < "$LOG")" -ne 15 ]]; then
  echo "ERROR: the sample log is not in its original 15-line state; restore it before injecting." >&2
  exit 1
fi
if [[ ! -f "$HOME/agentic-ai/logparse.py" ]]; then
  echo "ERROR: logparse.py not found. Finish Module 03 Build 04 first." >&2
  exit 1
fi

cp -p "$LOG" "$STATE_FILE"
printf '%s\n' \
  '2026-11-04 03:12:40 UTC [6010] ERROR:  canceling statement due to statement timeout' \
  '2026-11-04 03:12:40 UTC [6010] STATEMENT:  SELECT e.id, d.name' \
  $'\t  FROM employees e JOIN departments d ON d.id = e.department_id' \
  $'\t WHERE e.hired_on > now() - interval \'30 days\';' \
  '2026-11-04 03:13:02 UTC [6011] FATAL:  sorry, too many clients already' \
  >> "$LOG"

echo ""
echo "============================================================"
echo "  ALERT: the severity summary tool fails on every call"
echo "  It worked yesterday. Nobody changed the code. The"
echo "  database had a statement timeout a few minutes ago."
echo "============================================================"
echo ""
