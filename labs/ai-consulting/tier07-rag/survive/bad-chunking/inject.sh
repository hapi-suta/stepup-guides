#!/usr/bin/env bash
# SURVIVE inject: re-ingest the corpus with a BROKEN chunker.
#
# Chunking quality caps retrieval quality. This injects a common real mistake:
# tiny, fixed-size chunks that cut sentences mid-word. Facts get split across
# chunks so no single chunk cleanly answers a question, and retrieval returns
# fragments. No error is raised - answers just get worse.
#
# What this does:
#   - Monkey-patches rag.chunk_text at ingest time to a broken 40-char, no-
#     overlap, mid-word splitter, then re-ingests. rag.py itself is untouched;
#     the damage is in the INDEX (the stored chunks).
#
# Run as ec2-user, from the project directory, DB reachable + corpus present:
#   cd ~/project7 && bash /path/to/inject.sh
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/project7}"
cd "$PROJECT_DIR"

echo "[inject] re-ingesting with a broken (tiny, mid-word) chunker..."
python3 - <<'PY'
import rag, ingest

# Broken chunker: fixed 40-char slices, no sentence awareness, no overlap.
def bad_chunk(text, max_chars=40, overlap_chars=0):
    text = " ".join(text.split())
    return [text[i:i+40] for i in range(0, len(text), 40)] or []

rag.chunk_text = bad_chunk       # ingest.py calls rag.chunk_text
ingest.rag.chunk_text = bad_chunk
ingest.main()
print("[inject] index rebuilt with tiny fragmented chunks.")
PY

echo "[inject] DONE. Retrieval now returns fragmented, low-quality chunks."
echo "[inject] Follow runbook.md to diagnose and re-chunk, then run validate.sh."
