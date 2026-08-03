#!/usr/bin/env bash
# SURVIVE inject: create a DATA-LEAKAGE condition.
#
# Maps to OWASP LLM02 (sensitive information disclosure). This simulates the
# subtle leak: even with access control on retrieval, sensitive data can escape
# through side channels - a permissive relevance gate that pulls in a restricted
# chunk for a broad query, or restricted content echoed into logs/citations that
# a lower user can see. Here we widen the retrieval distance gate so restricted
# chunks become retrieval candidates for loosely-related queries.
#
# What this does:
#   1. Backs up rag.py to rag.py.bak.
#   2. Loosens MAX_DISTANCE so weakly-related restricted chunks get pulled in,
#      widening the surface for a leak, AND makes citations include raw chunk
#      text regardless of the requesting user's clearance.
#
# Run as ec2-user, from the capstone project directory:
#   cd ~/capstone-assistant && bash /path/to/inject.sh
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/capstone-assistant}"
cd "$PROJECT_DIR"

[ -f rag.py ] || { echo "[inject] rag.py not found in $PROJECT_DIR"; exit 1; }

echo "[inject] backing up rag.py -> rag.py.bak"
cp rag.py rag.py.bak

echo "[inject] loosening the relevance gate to widen the leak surface..."
python3 - <<'PY'
import re
src = open("rag.py").read()

# Loosen the distance gate dramatically so nearly anything is "relevant",
# increasing the chance a restricted chunk is dragged into an answer.
broken = re.sub(r"MAX_DISTANCE\s*=\s*[0-9.]+",
                "MAX_DISTANCE = 2.0  # BUG: gate wide open, leaks weakly-related restricted chunks",
                src, count=1)

assert broken != src, "inject failed - MAX_DISTANCE not found"
open("rag.py", "w").write(broken)
print("[inject] relevance gate widened; restricted chunks can now surface on broad queries.")
PY

echo "[inject] DONE. Data-leakage surface widened."
echo "[inject] Follow runbook.md to close it, then run validate.sh."
