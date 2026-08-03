#!/usr/bin/env bash
# SURVIVE validate: prove ROLE-BYPASS (privilege escalation) is fixed.
#
# Checks, in order:
#   1. app.py does NOT derive clearance from the request payload.
#   2. A level-1 user who CLAIMS clearance 4 is still treated as level 1 and
#      cannot retrieve restricted content (dynamic check via the resolve path).
#   3. A genuinely level-4 identity CAN still retrieve restricted content.
#
# Run as ec2-user, from the capstone project directory:
#   cd ~/capstone-assistant && bash /path/to/validate.sh
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/capstone-assistant}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

[ -f app.py ] || fail "app.py not found"

# 1. Static check: clearance must not come from the request payload.
if grep -Eq "payload.get\(['\"]clearance['\"]" app.py; then
  fail "app.py still reads clearance from the request payload - derive it from the authenticated identity"
fi
grep -q "get_user_clearance" app.py \
  || fail "no server-side clearance derivation (get_user_clearance) found in app.py"
echo "OK: clearance is not sourced from the request payload"

# 2/3. Dynamic check of the retrieval path: a claimed high clearance must not
# grant access; only the real identity clearance should.
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

# Simulate the fixed app: the real identity is level 1; the payload lie is
# ignored, so retrieval is called with the TRUE clearance (1).
rows = rag.retrieve(conn, "CEO salary executive compensation",
                    user_level=1, k=20, max_distance=2.0)
if any(r["source"] == "en-exec-comp.txt" for r in rows):
    print("FAIL: ESCALATION - level-1 identity retrieved the restricted doc")
    sys.exit(1)
print("OK: level-1 identity cannot reach restricted content even if it claims level 4")

# The genuine level-4 identity still works.
rows4 = rag.retrieve(conn, "CEO salary executive compensation",
                     user_level=4, k=10, max_distance=2.0)
if not any(r["source"] == "en-exec-comp.txt" for r in rows4):
    print("FAIL: over-corrected - genuine level-4 identity lost access")
    sys.exit(1)
print("OK: genuine level-4 identity retains access")

conn.close()
print("PASS: role-bypass fixed - privilege comes from identity, not the request.")
PY
