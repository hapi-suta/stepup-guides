#!/usr/bin/env bash
# SURVIVE validate: prove the access-control bypass is FIXED.
#
# This is the rigorous one. It checks, in order:
#   1. A level-1 (intern) user CANNOT retrieve any chunk from the restricted
#      exec-comp document, AND every chunk returned is access_level <= 1.
#   2. A level-1 user asking for the CEO salary gets a REFUSAL (no leak in the
#      generated answer either).
#   3. An authorized level-4 (board) user CAN still retrieve the restricted doc
#      (the fix must not over-correct into blocking legitimate access).
#   4. The access-control filter is present in the SQL of retrieve() (static
#      check), so the fix is in the query, not a fragile post-filter.
#
# Run as ec2-user, from the project directory, with the DB reachable and the
# corpus ingested:
#   cd ~/project7 && bash /path/to/validate.sh
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project7}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

[ -f rag.py ] || fail "rag.py not found"

# 4. Static check: the SQL must filter on access_level and user_level.
grep -q "access_level <= %(user_level)s" rag.py \
  || fail "the access_level filter is missing from retrieve()'s SQL - fix the query, not Python"
grep -q '1 = 1' rag.py \
  && fail "the injected 'WHERE 1 = 1' bug is still present in rag.py"
echo "OK: access-control filter is present in the SQL"

# Dynamic checks via Python (uses the real DB + retrieval path).
python3 - <<'PY' || exit 1
import sys, rag

try:
    conn = rag.db_conn()
except Exception as e:
    print(f"FAIL: database not reachable: {e}"); sys.exit(1)

with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM chunks")
    if cur.fetchone()[0] == 0:
        print("FAIL: corpus not ingested (no chunks)"); sys.exit(1)
    cur.execute("SELECT count(*) FROM chunks WHERE source = 'en-exec-comp.txt'")
    if cur.fetchone()[0] == 0:
        print("FAIL: restricted exec-comp doc not in corpus - re-ingest first"); sys.exit(1)

# 1. Intern (level 1) must not retrieve the restricted doc, at high k.
rows = rag.retrieve(conn, "CEO salary band executive compensation bonus equity",
                    user_level=1, k=20, max_distance=2.0)
if any(r["source"] == "en-exec-comp.txt" for r in rows):
    print("FAIL: SECURITY LEAK - level-1 user retrieved the restricted exec-comp doc")
    sys.exit(1)
if any(r["access_level"] > 1 for r in rows):
    print("FAIL: level-1 user retrieved a chunk above their clearance")
    sys.exit(1)
print("OK: level-1 user cannot retrieve any restricted chunk")

# 2. The generated answer for the intern must not leak the secret figure.
res = rag.answer(conn, "What is the CEO salary band?", user_level=1)
low = res["answer"].lower()
if "nine hundred thousand" in low or "900,000" in low or "900000" in low:
    print("FAIL: SECURITY LEAK - the answer to a level-1 user contains the restricted salary figure")
    sys.exit(1)
print("OK: level-1 answer does not leak the restricted figure")

# 3. Authorized board user (level 4) must still be able to retrieve it.
rows4 = rag.retrieve(conn, "CEO salary band executive compensation",
                     user_level=4, k=10, max_distance=2.0)
if not any(r["source"] == "en-exec-comp.txt" for r in rows4):
    print("FAIL: over-corrected - authorized level-4 user can no longer retrieve the doc")
    sys.exit(1)
print("OK: authorized level-4 user can still retrieve the restricted doc")

conn.close()
print("PASS: access control enforced - low clearance blocked, high clearance allowed.")
PY
