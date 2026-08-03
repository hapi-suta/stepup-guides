#!/usr/bin/env bash
# SURVIVE validate: prove the POISONED document is removed and not served.
#
# Checks, in order:
#   1. The poisoned 'en-fake-policy.txt' is NO LONGER in the served corpus
#      (chunks table).
#   2. An answer about submitting an application does NOT repeat the false
#      claims (in-person only / cash fee / no appeal).
#   3. Legitimate content is still present and answerable (no over-correction).
#
# Run as ec2-user, from the capstone project directory:
#   cd ~/capstone-assistant && bash /path/to/validate.sh
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/capstone-assistant}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }
[ -f rag.py ] || fail "rag.py not found"

python3 - <<'PY' || exit 1
import sys, rag

try:
    conn = rag.db_conn()
except Exception as e:
    print(f"FAIL: database not reachable: {e}"); sys.exit(1)

# 1. Poisoned doc must be gone from the served corpus.
with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM chunks WHERE source = 'en-fake-policy.txt'")
    if cur.fetchone()[0] != 0:
        print("FAIL: the poisoned document is still in the served corpus")
        sys.exit(1)
    cur.execute("SELECT count(*) FROM chunks")
    if cur.fetchone()[0] == 0:
        print("FAIL: corpus is empty - removed too much"); sys.exit(1)
print("OK: poisoned document is no longer served")

# 2. Answer must not repeat the false policy claims.
res = rag.answer(conn, "How do I submit a benefits application?", user_level=1)
ans = res["answer"].lower()
false_markers = ["in person only", "cash", "500 units", "no appeal", "non-refundable processing fee"]
hit = [m for m in false_markers if m in ans]
if hit:
    print(f"FAIL: answer still repeats false poisoned content: {hit}")
    sys.exit(1)
print("OK: answer does not repeat the false policy")

# 3. Legitimate corpus is still usable.
res2 = rag.answer(conn, "What are the office hours?", user_level=1)
if res2["answer"].strip() == "":
    print("FAIL: over-corrected - legitimate questions no longer answered")
    sys.exit(1)
print("OK: legitimate content still answerable")

conn.close()
print("PASS: poisoned document removed - false content no longer served.")
PY
