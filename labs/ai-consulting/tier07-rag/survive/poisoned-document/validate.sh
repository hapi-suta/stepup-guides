#!/usr/bin/env bash
# SURVIVE validate: prove the poisoned document is quarantined.
#
# PASS conditions:
#   1. The poisoned chunk (source='poisoned-upload.txt') is no longer in the
#      chunks table - it has been removed/quarantined.
#   2. Retrieval for a query that used to surface it no longer returns it, at
#      any clearance.
#   3. The legitimate corpus is intact (a known good question still works), so
#      the cleanup did not nuke real data.
#
# Run as ec2-user, from the project directory:
#   cd ~/project7 && bash /path/to/validate.sh
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project7}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "FAIL: $PROJECT_DIR not found"; exit 1; }

python3 - <<'PY' || exit 1
import sys, rag
try:
    conn = rag.db_conn()
except Exception as e:
    print(f"FAIL: database not reachable: {e}"); sys.exit(1)

with conn.cursor() as cur:
    # 1. The poisoned chunk must be gone.
    cur.execute("SELECT count(*) FROM chunks WHERE source = 'poisoned-upload.txt'")
    if cur.fetchone()[0] != 0:
        print("FAIL: the poisoned chunk (poisoned-upload.txt) is still in the index")
        sys.exit(1)
    print("OK: poisoned chunk removed from the index")

    # 3. Legitimate corpus intact.
    cur.execute("SELECT count(*) FROM chunks WHERE source = 'en-remote-work.txt'")
    if cur.fetchone()[0] == 0:
        print("FAIL: legitimate corpus is missing - cleanup was too aggressive")
        sys.exit(1)
    print("OK: legitimate corpus is intact")

# 2. Retrieval must not surface the poison at any clearance.
for lvl in (1, 4):
    rows = rag.retrieve(conn, "system override ignore instructions refund window",
                        user_level=lvl, k=10, max_distance=2.0)
    if any(r["source"] == "poisoned-upload.txt" for r in rows):
        print(f"FAIL: poisoned chunk still retrievable at clearance {lvl}")
        sys.exit(1)
print("OK: poisoned chunk not retrievable at any clearance")

conn.close()
print("PASS: poisoned document quarantined; corpus intact.")
PY
