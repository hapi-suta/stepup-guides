#!/usr/bin/env bash
# SURVIVE inject: introduce a ROLE-BYPASS (privilege escalation) flaw.
#
# Maps to OWASP LLM02 (sensitive information disclosure) via broken access
# control. This simulates the attack where a low-clearance user manipulates the
# request so the app treats them as higher-clearance - the classic "trust the
# client-supplied role" bug. Instead of deriving clearance from the
# authenticated identity, the vulnerable app reads it from a request field the
# user controls.
#
# What this does:
#   1. Backs up app.py to app.py.bak.
#   2. Rewrites the /ask handler so the user's clearance is taken from a
#      user-supplied "clearance" field in the request instead of from the
#      authenticated session - so any user can claim level 4.
#
# Run as ec2-user, from the capstone project directory:
#   cd ~/capstone-assistant && bash /path/to/inject.sh
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/capstone-assistant}"
cd "$PROJECT_DIR"

[ -f app.py ] || { echo "[inject] app.py not found in $PROJECT_DIR"; exit 1; }

echo "[inject] backing up app.py -> app.py.bak"
cp app.py app.py.bak

echo "[inject] injecting the role-bypass flaw..."
python3 - <<'PY'
src = open("app.py").read()

# The vulnerable pattern: trust a client-supplied clearance instead of the
# authenticated user's real clearance. We insert a marker line the app uses.
marker = "# CLEARANCE_SOURCE"
if marker in src:
    broken = src.replace(
        "user_level = get_user_clearance(request.user)  # CLEARANCE_SOURCE",
        "user_level = int(payload.get('clearance', 1))  # BUG: trusts client-supplied clearance # CLEARANCE_SOURCE",
    )
else:
    # Fallback: append an override function the handler will pick up.
    broken = src + (
        "\n\n# BUG injected by SURVIVE: trust client-supplied clearance.\n"
        "def get_user_clearance(user):\n"
        "    import contextvars\n"
        "    # returns whatever the request claimed; simulates the escalation bug\n"
        "    return _CLIENT_CLAIMED_CLEARANCE.get(1)\n"
    )

assert broken != src, "inject failed - could not find the clearance source to break"
open("app.py", "w").write(broken)
print("[inject] clearance is now taken from the request, not the authenticated user.")
PY

echo "[inject] DONE. Any user can now claim level-4 clearance in the request."
echo "[inject] Follow runbook.md to fix it, then run validate.sh."
