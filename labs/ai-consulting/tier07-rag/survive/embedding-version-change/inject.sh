#!/usr/bin/env bash
# SURVIVE inject: simulate an EMBEDDING-MODEL VERSION CHANGE that silently
# degrades retrieval.
#
# The classic silent RAG failure: someone "upgrades" the embedding model. The
# stored chunk vectors were made with the OLD model; new question vectors are
# made with the NEW model; comparing them is meaningless. Retrieval quietly
# returns garbage, but nothing errors and the service stays up.
#
# What this does:
#   - Rewrites every stored chunk vector by SHIFTING its components (a stand-in
#     for "vectors from a different model version"), and stamps the chunks with
#     a new embed_model name ('legacy-v0') that no longer matches what embed()
#     produces at query time. This reproduces the mismatch deterministically
#     without needing a second real model on the box.
#
# Run as ec2-user, from the project directory, DB reachable + corpus ingested:
#   cd ~/project7 && bash /path/to/inject.sh
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project7}"
cd "$PROJECT_DIR"

echo "[inject] corrupting stored vectors to simulate a stale embedding version..."
python3 - <<'PY'
import sys, rag
conn = rag.db_conn()
conn.autocommit = True
with conn.cursor() as cur:
    cur.execute("SELECT count(*) FROM chunks")
    if cur.fetchone()[0] == 0:
        print("[inject] FAIL: no chunks - ingest the corpus first"); sys.exit(1)
    cur.execute("SELECT id, embedding FROM chunks")
    rows = cur.fetchall()
    for cid, emb in rows:
        # emb comes back as the pgvector text '[a,b,c,...]'. Parse, rotate the
        # components by one position (a cheap deterministic "different model"),
        # and write it back. The magnitudes are unchanged but the DIRECTION is
        # now wrong relative to query embeddings from the current model.
        vals = [float(x) for x in emb.strip("[]").split(",")]
        rotated = vals[1:] + vals[:1]
        cur.execute("UPDATE chunks SET embedding = %s::vector, embed_model = %s WHERE id = %s",
                    (rag.to_pgvector(rotated), "legacy-v0", cid))
print(f"[inject] rewrote {len(rows)} chunk vectors and stamped them embed_model='legacy-v0'.")
print("[inject] Query embeddings now come from a DIFFERENT model than the stored vectors.")
conn.close()
PY

echo "[inject] DONE. Retrieval will now return irrelevant chunks with no error."
echo "[inject] Follow runbook.md to detect the mismatch and re-index, then run validate.sh."
