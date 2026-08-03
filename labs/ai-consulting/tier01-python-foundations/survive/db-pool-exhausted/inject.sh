#!/usr/bin/env bash
# SURVIVE inject: break Project 1's database connection with bad credentials.
#
# Simulates the single most common production incident: the app cannot reach
# the database because its credentials are wrong (rotated password not updated,
# typo in a config change, pointed at the wrong host).
#
# What this does:
#   1. Saves the current good DB_PASSWORD to a restore file (so validate/you
#      can prove recovery).
#   2. Writes a project .env with a WRONG password.
#   3. Starts the API using that broken env, in the background.
#
# Run as ec2-user. Requires Project 1 in ~/project1 with the .venv from BUILD.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project1}"
cd "$PROJECT_DIR"

echo "[inject] stopping any running app on port 8000..."
pkill -f "uvicorn app:app" 2>/dev/null || true
sleep 1

# Remember the known-good password so recovery is provable.
echo "labpass" > .db_password.good
echo "[inject] saved known-good password to .db_password.good"

# Write a broken environment file the app will read.
cat > .env <<'EOF'
DB_HOST=127.0.0.1
DB_NAME=labdb
DB_USER=labuser
DB_PASSWORD=WRONG-PASSWORD-INJECTED
EOF
echo "[inject] wrote .env with a WRONG DB_PASSWORD"

# Start the app with the broken credentials (export the .env vars).
set -a
# shellcheck disable=SC1091
. ./.env
set +a

if [ ! -d .venv ]; then
  echo "[inject] ERROR: .venv not found. Run the BUILD guide first." >&2
  exit 1
fi

nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
sleep 3

echo "[inject] app started with broken credentials."
echo "[inject] DONE. The app is up but cannot reach the database."
echo "[inject] Try:  curl -s http://127.0.0.1:8000/health"
echo "[inject] Then follow runbook.md to diagnose and recover."
