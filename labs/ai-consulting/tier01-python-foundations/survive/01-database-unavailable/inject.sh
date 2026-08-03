#!/usr/bin/env bash
#
# SURVIVE scenario: database unavailable
# Breaks the environment by stopping PostgreSQL while the API is running.
# The student must diagnose why /summary fails and recover the service.
#
# Run on the lab server as ec2-user.
set -euo pipefail

echo "[inject] Ensuring the API is running ..."
cd ~/project1
source .venv/bin/activate 2>/dev/null || true
if ! pgrep -f "uvicorn app:app" >/dev/null; then
  nohup uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
  sleep 3
fi

echo "[inject] Stopping PostgreSQL to simulate a database outage ..."
sudo systemctl stop postgresql

echo "[inject] Done. The API is up but the database is down."
echo "[inject] Try:  curl -s http://127.0.0.1:8000/summary"
echo "[inject] Then work through runbook.md to diagnose and recover."
