#!/usr/bin/env bash
# SURVIVE validate: prove the index was re-chunked sensibly.
#
# PASS conditions:
#   1. Chunks are no longer tiny fragments: the average chunk length is well
#      above the broken 40-char size (sentence/paragraph-aware chunking).
#   2. A known question retrieves its expected document with a good (low)
#      distance, i.e. retrieval quality recovered.
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
    cur.execute("SELECT count(*), coalesce(avg(length(chunk_text)),0) FROM chunks")
    n, avg_len = cur.fetchone()
    if n == 0:
        print("FAIL: no chunks - re-ingest the corpus"); sys.exit(1)

# 1. Chunks must not be tiny fragments.
if avg_len < 150:
    print(f"FAIL: average chunk length is {avg_len:.0f} chars - still fragmented. "
          f"Re-chunk with sentence/paragraph-aware chunking.")
    sys.exit(1)
print(f"OK: average chunk length is {avg_len:.0f} chars (not fragmented)")

# 2. Retrieval quality recovered: expected doc near the top with a good distance.
rows = rag.retrieve(conn, "remote work probation period", user_level=1, k=3, max_distance=2.0)
if not rows:
    print("FAIL: retrieval returned nothing"); sys.exit(1)
top = rows[0]
if top["source"] != "en-remote-work.txt":
    print(f"FAIL: top result is {top['source']}, expected en-remote-work.txt")
    sys.exit(1)
if top["distance"] > 0.75:
    print(f"FAIL: top distance {top['distance']:.3f} is poor - retrieval not recovered")
    sys.exit(1)
print(f"OK: retrieval recovered (top={top['source']}, distance={top['distance']:.3f})")

conn.close()
print("PASS: index re-chunked sensibly and retrieval quality restored.")
PY
