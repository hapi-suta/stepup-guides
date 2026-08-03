#!/usr/bin/env bash
# SURVIVE validate: confirm the secret was removed from tracked files and
# config now reads from the environment.
#
# PASS conditions:
#   1. No hardcoded secret (sk-live-... or a plaintext password) in any
#      tracked file.
#   2. config.py reads secrets from os.environ.
#   3. .env is git-ignored (not tracked).
#
# Run as ec2-user after following runbook.md.
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project1}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

[ -d .git ] || fail "no git repo found - run inject.sh first"

# 1. No hardcoded secret in tracked files.
if git grep -qE "sk-live-[0-9a-f]{16,}" -- '*.py' 2>/dev/null; then
  echo "--- offending lines ---"; git grep -nE "sk-live-[0-9a-f]{16,}" -- '*.py'
  fail "a hardcoded API key is still present in a tracked file"
fi
echo "OK: no hardcoded API key in tracked files"

if git grep -qE '(API_KEY|DB_PASSWORD)[[:space:]]*=[[:space:]]*"[^"]+"' -- '*.py' 2>/dev/null; then
  echo "--- offending lines ---"
  git grep -nE '(API_KEY|DB_PASSWORD)[[:space:]]*=[[:space:]]*"[^"]+"' -- '*.py'
  fail "a secret is still assigned a literal string value in a tracked file"
fi
echo "OK: no literal secret assignments in tracked files"

# 2. config.py must read from the environment.
if [ -f config.py ]; then
  if ! grep -q "os.environ" config.py; then
    fail "config.py does not read secrets from os.environ"
  fi
  echo "OK: config.py reads secrets from the environment"
fi

# 3. .env must be git-ignored (if present).
if [ -f .env ]; then
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then
    fail ".env is tracked by git - it must be ignored"
  fi
  echo "OK: .env exists and is git-ignored"
fi

echo "PASS: secret removed from tracked files; config reads from environment."
