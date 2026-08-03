#!/usr/bin/env bash
#
# SURVIVE scenario: git-disaster
# inject.sh - commits a fake secret into a git repository.
#
# What this does (the "break"):
#   1. Creates a throwaway git repo at ~/survive-git-lab.
#   2. Writes a fake API key into a file called config.py.
#   3. Commits config.py (with the secret) across TWO commits so the secret
#      is baked into the repo's HISTORY, not just the latest commit.
#
# The student's job: get the secret OUT of the tracked files (and ideally out
# of history), and move it to an environment variable instead.
#
# Safe to run on CentOS Stream 9 as ec2-user. Self-contained. Idempotent.
# The "secret" is fake - it is not a real credential.

set -u

LAB_DIR="${HOME}/survive-git-lab"

echo "[inject] Setting up git-disaster scenario in ${LAB_DIR}"

rm -rf "${LAB_DIR}"
mkdir -p "${LAB_DIR}"
cd "${LAB_DIR}" || exit 1

# Make sure git has an identity so commits succeed even on a clean box.
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "SUTA Student"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "student@example.com"

git init -q
git branch -M main 2>/dev/null || true

# First commit: an innocent file.
cat > app.py <<'EOF'
# Tiny demo app
def main():
    print("hello from the app")

if __name__ == "__main__":
    main()
EOF
git add app.py
git commit -q -m "Add demo app"

# BREAK: create a config file with a hard-coded fake secret and commit it.
cat > config.py <<'EOF'
# Application configuration
# WARNING: a secret was hard-coded here by mistake.
API_KEY = "sk-fake-1234567890ABCDEFsecretDONOTCOMMIT"
DB_HOST = "127.0.0.1"
EOF
git add config.py
git commit -q -m "Add config with API key"

# Second commit touching the file too, so the secret is spread through history.
echo 'DB_PORT = 5432' >> config.py
git add config.py
git commit -q -m "Add DB port to config"

echo
echo "[inject] DONE. A fake secret is now committed in ${LAB_DIR}/config.py"
echo "[inject] and baked into the git HISTORY across multiple commits."
echo "[inject] Your job: remove the secret from tracked files, move it to an"
echo "[inject] environment variable, and ignore config.py going forward."
echo "[inject] See runbook.md. Then run: bash validate.sh"
