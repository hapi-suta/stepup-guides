#!/usr/bin/env bash
# SURVIVE inject: an auth misconfiguration exposes an admin endpoint.
#
# What this simulates: someone added an "internal" admin endpoint in a hurry
# and forgot the authorization dependency. The route reads sensitive data
# (every user's role, clearance, and bearer token) but is reachable by ANYONE
# with no login and no admin role - the single most common real-world API flaw
# (OWASP "Broken Access Control").
#
# What this does:
#   1. Backs up app.py.
#   2. Appends a new /admin/debug/users route that has NO auth dependency.
#   3. Restarts the API so the bad route is live.
#
# Run as ec2-user, with Project 9 in ~/project9 and the .venv from BUILD.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project9}"
cd "$PROJECT_DIR"

echo "[inject] backing up app.py -> app.py.orig"
cp app.py app.py.orig

echo "[inject] appending an UNPROTECTED admin route to app.py..."
cat >> app.py <<'PYEOF'


# ----- INJECTED BY SURVIVE (auth misconfiguration) -----
# BUG: this admin route has NO auth dependency. It leaks every user's token.
@app.get("/admin/debug/users")
def admin_debug_users() -> dict:
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT username, role, clearance, api_token FROM app_users ORDER BY id")
            rows = cur.fetchall()
    return {"users": [{"username": r[0], "role": r[1], "clearance": r[2],
                       "api_token": r[3]} for r in rows]}
# ----- END INJECTED -----
PYEOF

echo "[inject] restarting the API..."
pkill -f "uvicorn app:app" 2>/dev/null || true
sleep 1
set -a; . ./.env 2>/dev/null || true; set +a
nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
sleep 3

echo "[inject] DONE. An unauthenticated caller can now read all tokens:"
echo "[inject]   curl -s http://127.0.0.1:8000/admin/debug/users"
echo "[inject] Follow runbook.md to detect and lock it down."
