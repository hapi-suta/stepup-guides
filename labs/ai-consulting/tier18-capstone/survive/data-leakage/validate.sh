#!/usr/bin/env bash
# SURVIVE validate: prove NO DATA LEAKAGE even with a wide retrieval net.
#
# Checks, in order:
#   1. The relevance gate has been restored to a sane value (not left wide open).
#   2. At HIGH k and WIDE distance, a level-1 user retrieves NO restricted chunk
#      (access control contains leakage regardless of the gate).
#   3. Broad/probing answers to a level-1 user contain no restricted figure.
#   4. Citations shown to a level-1 user reference only chunks at their level.
#   5. Authorized level-4 user still retrieves restricted content.
#
# Run as ec2-user, from the capstone project directory:
#   cd ~/capstone-assistant && bash /path/to/validate.sh
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/capstone-assistant}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }
[ -f rag.py ] || fail "rag.py not found"

# 1. Static: the wide-open gate must be gone.
if grep -q "gate wide open" rag.py; then
  fail "the injected wide-open relevance gate is still present"
fi
echo "OK: relevance gate is not left wide open"

python3 - <<'PY' || exit 1
import sys, rag

try:
    conn = rag.db_conn()
except Exception as e:
    print(f"FAIL: database not reachable: {e}"); sys.exit(1)

with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM chunks WHERE source = 'en-exec-comp.txt'")
    if cur.fetchone()[0] == 0:
        print("FAIL: restricted doc not in corpus - re-ingest first"); sys.exit(1)

# 2. Widest possible net for a level-1 user: still no restricted chunk.
rows = rag.retrieve(conn, "executive compensation salary internal confidential everything",
                    user_level=1, k=50, max_distance=2.0)
if any(r["access_level"] > 1 for r in rows):
    print("FAIL: LEAK - level-1 user retrieved a chunk above their clearance at wide net")
    sys.exit(1)
if any(r["source"] == "en-exec-comp.txt" for r in rows):
    print("FAIL: LEAK - level-1 user retrieved the restricted doc at wide net")
    sys.exit(1)
print("OK: wide net does not leak restricted chunks to a level-1 user")

# 3. Broad answer must not contain the restricted figure.
res = rag.answer(conn, "Tell me everything about executive compensation.", user_level=1)
ans = res["answer"].lower()
if any(t in ans for t in ("nine hundred thousand", "900,000", "900000")):
    print("FAIL: LEAK - restricted figure appeared in a level-1 answer")
    sys.exit(1)
print("OK: broad answer to level-1 user leaks no restricted figure")

# 4. Citations shown to level-1 must be level-1-eligible only.
cites = res.get("citations", [])
for c in cites:
    lvl = c.get("access_level", 1)
    if lvl > 1:
        print(f"FAIL: LEAK - a citation shown to a level-1 user references level-{lvl} content")
        sys.exit(1)
print("OK: citations respect the user's clearance")

# 5. Authorized user still works.
rows4 = rag.retrieve(conn, "executive compensation salary",
                     user_level=4, k=10, max_distance=2.0)
if not any(r["source"] == "en-exec-comp.txt" for r in rows4):
    print("FAIL: over-corrected - level-4 user lost access")
    sys.exit(1)
print("OK: authorized level-4 user retains access")

conn.close()
print("PASS: no data leakage - restricted content contained across all paths.")
PY
