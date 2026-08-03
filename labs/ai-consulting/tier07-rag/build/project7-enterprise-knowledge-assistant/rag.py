"""Core RAG library for Project 7 - the enterprise knowledge assistant.

This module is deliberately free of web framework code so it can be imported by
app.py, ingest.py, eval_harness.py, the tests, and the SURVIVE scenarios alike.

Design goals:
- Runs OFFLINE on a small CPU box: embedding falls back to a deterministic
  hashing embedding when sentence-transformers is not installed; generation
  falls back to a MOCK generator when ANTHROPIC_API_KEY is not set.
- Access control is enforced IN THE SQL query, never post-filtered in Python.
- Every retrieved chunk carries the metadata needed to cite it.
"""

from __future__ import annotations

import hashlib
import math
import os
import re
from typing import Any

import psycopg2
import psycopg2.extras

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

EMBED_DIM = 384  # vector dimensionality; matches the vector(384) column
# The model name is stored alongside every vector so a later model change is
# detectable (see the embedding-version-change SURVIVE scenario).
HASH_MODEL_NAME = "hashing-v1"

# Retrieval relevance gate. Cosine distance ranges 0 (identical) .. 2 (opposite).
# If even the closest chunk is farther than this, the corpus almost certainly
# does not contain the answer, so we retrieve nothing and the generator refuses.
# This is what makes the system say "I don't have that information" instead of
# answering from a weakly-related chunk. Tune per corpus/embedding model.
MAX_DISTANCE = 0.75


def db_conn():
    """Open a PostgreSQL connection using environment variables.

    Falls back to the lab defaults (labuser/labpass/labdb on localhost).
    """
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "127.0.0.1"),
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ.get("DB_NAME", "labdb"),
        user=os.environ.get("DB_USER", "labuser"),
        password=os.environ.get("DB_PASSWORD", "labpass"),
    )


# ---------------------------------------------------------------------------
# Embedding
# ---------------------------------------------------------------------------

# Try to load a small CPU sentence-transformers model once. If it is not
# installed (the common offline case), _MODEL stays None and we use hashing.
_MODEL = None
_MODEL_NAME = HASH_MODEL_NAME
try:  # pragma: no cover - depends on the box having the package + weights
    from sentence_transformers import SentenceTransformer

    _MODEL = SentenceTransformer("all-MiniLM-L6-v2")  # 384-dim, CPU-friendly
    _MODEL_NAME = "all-MiniLM-L6-v2"
except Exception:
    _MODEL = None
    _MODEL_NAME = HASH_MODEL_NAME


def embed_model_name() -> str:
    """Return the name of the embedding model currently in use.

    Stored with each vector so a mismatch (old vectors, new model) is
    detectable rather than silent.
    """
    return _MODEL_NAME


def _hashing_embed(text: str) -> list[float]:
    """Deterministic, dependency-free embedding.

    Each token deterministically bumps a handful of vector positions. The
    result captures word overlap (not deep meaning), which is enough to prove
    the whole pipeline and to make tests reproducible. Same text -> same vector.
    """
    vec = [0.0] * EMBED_DIM
    tokens = re.findall(r"[a-z0-9]+", text.lower())
    for tok in tokens:
        # Two independent hash positions per token so vectors are less collision-prone.
        h1 = int(hashlib.md5(tok.encode()).hexdigest(), 16)
        h2 = int(hashlib.sha1(tok.encode()).hexdigest(), 16)
        vec[h1 % EMBED_DIM] += 1.0
        vec[h2 % EMBED_DIM] += 0.5
    # L2-normalise so cosine distance behaves well.
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


def embed(text: str) -> list[float]:
    """Embed a single string into a 384-dim vector.

    Uses the sentence-transformers model if available, otherwise the hashing
    fallback. Downstream code does not care which path ran.
    """
    if _MODEL is not None:  # pragma: no cover - only on boxes with the model
        v = _MODEL.encode(text, normalize_embeddings=True)
        return [float(x) for x in v]
    return _hashing_embed(text)


def to_pgvector(vec: list[float]) -> str:
    """Render a Python list as a pgvector literal, e.g. '[0.1,0.2,...]'."""
    return "[" + ",".join(f"{x:.6f}" for x in vec) + "]"


# ---------------------------------------------------------------------------
# Chunking
# ---------------------------------------------------------------------------


def chunk_text(text: str, max_chars: int = 600, overlap_chars: int = 80) -> list[str]:
    """Split text into paragraph-aware chunks with a little overlap.

    We split on blank lines first (natural boundaries), then pack paragraphs
    into chunks up to max_chars, carrying a small overlap so a fact that
    straddles a boundary is not lost. Deliberately simple and correct - the
    bad-chunking SURVIVE scenario shows what happens when this is broken.
    """
    text = text.strip()
    if not text:
        return []
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks: list[str] = []
    current = ""
    for para in paragraphs:
        if current and len(current) + len(para) + 1 > max_chars:
            chunks.append(current.strip())
            # start next chunk with an overlap tail of the previous chunk
            tail = current[-overlap_chars:] if overlap_chars else ""
            current = (tail + " " + para).strip()
        else:
            current = (current + "\n" + para).strip() if current else para
    if current.strip():
        chunks.append(current.strip())
    return chunks


# ---------------------------------------------------------------------------
# Retrieval  (access control enforced in SQL)
# ---------------------------------------------------------------------------


def retrieve(
    conn,
    query: str,
    user_level: int,
    lang: str | None = None,
    k: int = 5,
    max_distance: float = MAX_DISTANCE,
) -> list[dict[str, Any]]:
    """Return the top-k chunks the user is allowed to see, closest to the query.

    SECURITY: access control is a WHERE clause in the SQL. Forbidden rows never
    leave the database. Do NOT fetch everything and filter in Python.

    RELEVANCE: chunks farther than max_distance are dropped, so an unanswerable
    question retrieves nothing (and the generator then refuses) rather than
    grabbing a weakly-related chunk. Set max_distance high (e.g. 2.0) to disable.
    """
    qvec = to_pgvector(embed(query))
    sql = """
        SELECT c.id, c.chunk_text, c.source, c.page, c.access_level,
               c.lang, d.title,
               c.embedding <=> %(qvec)s::vector AS distance
        FROM chunks c
        JOIN documents d ON d.id = c.doc_id
        WHERE c.access_level <= %(user_level)s
    """
    params: dict[str, Any] = {"qvec": qvec, "user_level": user_level}
    if lang:
        sql += " AND c.lang = %(lang)s"
        params["lang"] = lang
    sql += " ORDER BY distance ASC LIMIT %(k)s"
    params["k"] = k

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    # Relevance gate: drop chunks that are too far to plausibly answer the query.
    return [dict(r) for r in rows if r["distance"] <= max_distance]


# ---------------------------------------------------------------------------
# Prompt construction + generation
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = (
    "You are an enterprise knowledge assistant. Answer the user's question "
    "using ONLY the numbered context passages provided. If the answer is not "
    "in the context, reply exactly: \"I don't have that information.\" "
    "Cite the passages you used by their number in square brackets, e.g. [1]. "
    "Do not use any knowledge outside the context."
)


def build_prompt(query: str, chunks: list[dict[str, Any]]) -> str:
    """Assemble the user-facing prompt: numbered context + the question."""
    context_lines = []
    for i, ch in enumerate(chunks, start=1):
        context_lines.append(f"[{i}] (source: {ch['source']}) {ch['chunk_text']}")
    context = "\n\n".join(context_lines) if context_lines else "(no context found)"
    return f"Context passages:\n{context}\n\nQuestion: {query}\n\nAnswer:"


def _mock_generate(query: str, chunks: list[dict[str, Any]]) -> str:
    """Offline generator: no API key needed.

    Demonstrates grounded, cited answering deterministically so retrieval and
    citation can be shown and TESTED without a paid key. It stitches together
    the retrieved chunks and cites them; if there is no context it refuses.
    This is NOT a language model - it proves the plumbing, not the fluency.
    """
    if not chunks:
        return "I don't have that information."
    # Take the single most relevant chunk (smallest distance = first) as the
    # grounded answer body, and cite it. Keep it short and quote real text.
    top = chunks[0]
    snippet = top["chunk_text"].strip().replace("\n", " ")
    if len(snippet) > 300:
        snippet = snippet[:300].rsplit(" ", 1)[0] + "..."
    return f"[MOCK] Based on the retrieved context: {snippet} [1]"


def generate(query: str, chunks: list[dict[str, Any]]) -> tuple[str, str]:
    """Generate an answer. Returns (answer_text, generator_name).

    Uses Claude when ANTHROPIC_API_KEY is set; otherwise the mock generator.
    Real-key path is clearly separated so the demo runs offline by default.
    """
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return _mock_generate(query, chunks), "mock"

    # --- Real key path: call Claude via the official Anthropic SDK. ---------
    try:  # pragma: no cover - only exercised when a real key is present
        import anthropic

        client = anthropic.Anthropic(api_key=api_key)
        prompt = build_prompt(query, chunks)
        resp = client.messages.create(
            model="claude-opus-4-8",
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": prompt}],
        )
        text = next((b.text for b in resp.content if b.type == "text"), "")
        return text, "claude-opus-4-8"
    except Exception as exc:  # never crash the endpoint on a provider error
        # Fail closed to the mock so the demo keeps working; surface the reason.
        return _mock_generate(query, chunks) + f" (LLM error: {exc})", "mock-fallback"


def answer(conn, query: str, user_level: int, lang: str | None = None, k: int = 5) -> dict[str, Any]:
    """End-to-end: retrieve -> generate -> return answer with citations.

    This is the one function the API endpoint and the eval harness both call.
    """
    chunks = retrieve(conn, query, user_level=user_level, lang=lang, k=k)
    text, generator = generate(query, chunks)
    citations = [
        {"n": i + 1, "source": ch["source"], "page": ch["page"], "title": ch["title"]}
        for i, ch in enumerate(chunks)
    ]
    return {
        "answer": text,
        "generator": generator,
        "embed_model": embed_model_name(),
        "citations": citations,
        "retrieved": len(chunks),
    }
