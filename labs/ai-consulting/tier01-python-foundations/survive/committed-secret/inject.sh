#!/usr/bin/env bash
# SURVIVE inject: hardcode a secret into source and commit it to git.
#
# Simulates the most common security failure in real codebases: an API key
# hardcoded in a source file and committed. Once committed, the secret is in
# git history forever - "deleting" the line does not remove it.
#
# What this does:
#   1. Ensures ~/project1 is a git repo.
#   2. Creates config.py with a HARDCODED fake API key.
#   3. Commits it, so the secret is now in tracked files AND history.
#
# Run as ec2-user. Requires Project 1 in ~/project1.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project1}"
cd "$PROJECT_DIR"

# Make sure we have a git repo to leak into.
if [ ! -d .git ]; then
  echo "[inject] initializing a git repo in $PROJECT_DIR..."
  git init -q
  git config user.email "student@suta.local"
  git config user.name "SUTA Student"
fi

echo "[inject] writing config.py with a HARDCODED secret..."
cat > config.py <<'PY'
"""App config. DO NOT hardcode secrets here - fix this in the runbook."""

# BAD: a real API key hardcoded in source and about to be committed.
API_KEY = "sk-live-4f9a1c7e2b8d0a6f3e5c9b1d7a4f2e8c"

# BAD: the database password hardcoded too.
DB_PASSWORD = "labpass"

DB_HOST = "127.0.0.1"
DB_NAME = "labdb"
DB_USER = "labuser"
PY

git add config.py
git commit -q -m "add app config"

echo "[inject] committed config.py containing a hardcoded secret."
echo "[inject] The secret 'sk-live-...' is now in a tracked file AND git history."
echo "[inject] DONE. Follow runbook.md to rotate, move to env vars, and scrub."
