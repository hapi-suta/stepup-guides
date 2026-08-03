"""Ingest the corpus into PostgreSQL: parse -> clean -> chunk -> embed -> store.

Reads corpus/manifest.csv, loads each text file, chunks it, embeds each chunk,
and inserts documents + chunks with full metadata (source, access_level, lang,
embed_model, content_hash for dedup). Idempotent: it clears and reloads.

Run as ec2-user:  python ingest.py
"""

from __future__ import annotations

import csv
import hashlib
import os

import rag


def clean(text: str) -> str:
    """Minimal cleaning: strip trailing whitespace on each line, drop blanks-only runs."""
    lines = [ln.rstrip() for ln in text.splitlines()]
    return "\n".join(lines).strip()


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    corpus_dir = os.path.join(here, "corpus")
    manifest = os.path.join(corpus_dir, "manifest.csv")

    conn = rag.db_conn()
    conn.autocommit = False
    model = rag.embed_model_name()
    print(f"[ingest] embedding model: {model}")

    with conn.cursor() as cur:
        # Idempotent reload: clear existing content (CASCADE drops chunks).
        cur.execute("DELETE FROM documents;")

        seen_hashes: set[str] = set()
        n_docs = n_chunks = n_dupes = 0

        with open(manifest, newline="") as f:
            for row in csv.DictReader(f):
                path = os.path.join(corpus_dir, row["filename"])
                with open(path, encoding="utf-8") as fh:
                    text = clean(fh.read())

                access_level = int(row["access_level"])
                lang = row["lang"]
                cur.execute(
                    "INSERT INTO documents (title, source, lang, access_level) "
                    "VALUES (%s, %s, %s, %s) RETURNING id",
                    (row["title"], row["filename"], lang, access_level),
                )
                doc_id = cur.fetchone()[0]
                n_docs += 1

                for chunk in rag.chunk_text(text):
                    chash = hashlib.sha256(chunk.encode()).hexdigest()
                    if chash in seen_hashes:  # dedup identical chunks
                        n_dupes += 1
                        continue
                    seen_hashes.add(chash)
                    vec = rag.to_pgvector(rag.embed(chunk))
                    cur.execute(
                        "INSERT INTO chunks (doc_id, chunk_text, embedding, source, "
                        "page, access_level, lang, embed_model, content_hash) "
                        "VALUES (%s, %s, %s::vector, %s, %s, %s, %s, %s, %s)",
                        (doc_id, chunk, vec, row["filename"], 1,
                         access_level, lang, model, chash),
                    )
                    n_chunks += 1

    conn.commit()
    conn.close()
    print(f"[ingest] loaded {n_docs} documents, {n_chunks} chunks "
          f"({n_dupes} duplicate chunks skipped)")


if __name__ == "__main__":
    main()
