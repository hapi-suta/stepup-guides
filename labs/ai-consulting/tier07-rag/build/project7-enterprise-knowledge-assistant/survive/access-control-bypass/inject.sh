#!/usr/bin/env bash
# SURVIVE inject: introduce an ACCESS-CONTROL BYPASS in the retrieval query.
#
# THE MOST IMPORTANT SCENARIO IN THIS TIER. This simulates the single worst
# failure an enterprise RAG system can have: a filter bug that lets a
# low-clearance user retrieve a document they must NOT see. In production this
# is a data breach, not a bug ticket.
#
# What this does:
#   1. Backs up rag.py to rag.py.bak (so you can compare).
#   2. Rewrites retrieve() so the access-control WHERE clause is applied to the
#      DOCUMENT but silently NOT to the chunk rows actually returned - a classic
#      real bug where the developer "filtered" in the wrong place. The result:
#      a level-1 user can now retrieve chunks from the RESTRICTED exec-comp doc.
#
# Run as ec2-user, from the project directory:
#   cd ~/project7 && bash /path/to/inject.sh
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project7}"
cd "$PROJECT_DIR"

[ -f rag.py ] || { echo "[inject] rag.py not found in $PROJECT_DIR"; exit 1; }

echo "[inject] backing up rag.py -> rag.py.bak"
cp rag.py rag.py.bak

echo "[inject] injecting the access-control bypass into retrieve()..."
python3 - <<'PY'
import re
src = open("rag.py").read()

# Break the security filter: comment out the access_level WHERE condition so
# EVERY chunk (including restricted ones) is a retrieval candidate. This is the
# essence of the bug - the filter that should be in the query is gone.
broken = src.replace(
    "        WHERE c.access_level <= %(user_level)s\n",
    "        WHERE 1 = 1  -- BUG: access_level filter removed\n",
)
# Also remove the reference to user_level so the (now unused) param does not error.
broken = broken.replace(
    '    params: dict[str, Any] = {"qvec": qvec, "user_level": user_level}',
    '    params: dict[str, Any] = {"qvec": qvec}  # BUG: user_level no longer applied',
)

assert broken != src, "inject failed - the target lines were not found"
open("rag.py", "w").write(broken)
print("[inject] retrieve() now returns chunks regardless of the user's clearance.")
PY

echo "[inject] DONE. A low-clearance user can now retrieve restricted documents."
echo "[inject] Follow runbook.md to detect and fix the leak, then run validate.sh."
