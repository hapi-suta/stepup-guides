#!/usr/bin/env bash
# SURVIVE validate: prove the embedding-version mismatch is fixed (re-indexed).
#
# PASS conditions:
#   1. Every stored chunk's embed_model matches the model embed() uses now
#      (no 'legacy-v0' left behind) - detection of the mismatch is resolved.
#   2. Retrieval works again: a known question retrieves its expected document.
#
# Run as ec2-user, from the project directory, DB reachable + corpus ingested:
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

current = rag.embed_model_name()
with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM chunks")
    if cur.fetchone()[0] == 0:
        print("FAIL: corpus not ingested"); sys.exit(1)
    # 1. No chunk may still carry a model name other than the current one.
    cur.execute("SELECT DISTINCT embed_model FROM chunks")
    models = {r[0] for r in cur.fetchall()}

if models != {current}:
    print(f"FAIL: stored vectors were made with {models}, but embed() now uses "
          f"'{current}'. Re-index (re-embed) all chunks with the current model.")
    sys.exit(1)
print(f"OK: all chunks embedded with the current model '{current}'")

# 2. Retrieval must work again for a known question.
rows = rag.retrieve(conn, "remote work probation period", user_level=1, k=3, max_distance=2.0)
if not rows or not any(r["source"] == "en-remote-work.txt" for r in rows):
    print("FAIL: retrieval still broken - expected en-remote-work.txt near the top")
    sys.exit(1)
print("OK: retrieval returns the expected document again")

conn.close()
print("PASS: embedding version consistent and retrieval restored.")
PY
