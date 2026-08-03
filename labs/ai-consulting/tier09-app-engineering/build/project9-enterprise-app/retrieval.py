"""Retrieval + answer generation for Project 9.

This is a deliberately small, dependency-light version of the Tier 7 RAG core.
It retrieves chunks the user is cleared to see (access control in SQL), then
generates a grounded answer. Generation calls Claude when ANTHROPIC_API_KEY is
set, and otherwise uses an offline MOCK so every lab and test runs with no key.

Retrieval here uses simple keyword overlap so the project needs no vector
extension - the point of Tier 9 is enterprise plumbing, not embedding math,
which you already built in Tier 7.
"""
from __future__ import annotations

import os
import re
from typing import Any


def _tokens(text: str) -> set[str]:
    """Lowercase word set, for cheap keyword-overlap scoring."""
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def retrieve(conn, query: str, user_clearance: int, k: int = 3) -> list[dict[str, Any]]:
    """Return up to k chunks the user may see, ranked by keyword overlap.

    SECURITY: access control is a WHERE clause in the SQL. Chunks above the
    user's clearance never leave the database - we do not fetch everything and
    filter in Python.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, chunk_text, source, access_level "
            "FROM chunks WHERE access_level <= %s",
            (user_clearance,),
        )
        rows = cur.fetchall()

    q = _tokens(query)
    scored = []
    for cid, text, source, level in rows:
        overlap = len(q & _tokens(text))
        if overlap > 0:
            scored.append({"id": cid, "chunk_text": text, "source": source,
                           "access_level": level, "score": overlap})
    scored.sort(key=lambda r: r["score"], reverse=True)
    return scored[:k]


SYSTEM_PROMPT = (
    "You are an enterprise knowledge assistant. Answer using ONLY the numbered "
    "context passages. If the answer is not in the context, reply exactly: "
    "\"I don't have that information.\" Cite passages by number, e.g. [1]."
)


def _build_prompt(query: str, chunks: list[dict[str, Any]]) -> str:
    lines = [f"[{i}] (source: {c['source']}) {c['chunk_text']}"
             for i, c in enumerate(chunks, start=1)]
    context = "\n\n".join(lines) if lines else "(no context found)"
    return f"Context passages:\n{context}\n\nQuestion: {query}\n\nAnswer:"


def _mock_generate(query: str, chunks: list[dict[str, Any]]) -> str:
    """Offline generator - no API key needed. Proves the plumbing, not fluency."""
    if not chunks:
        return "I don't have that information."
    snippet = chunks[0]["chunk_text"].strip().replace("\n", " ")
    if len(snippet) > 280:
        snippet = snippet[:280].rsplit(" ", 1)[0] + "..."
    return f"[MOCK] Based on the retrieved context: {snippet} [1]"


def generate(query: str, chunks: list[dict[str, Any]]) -> tuple[str, str]:
    """Return (answer_text, generator_name). Mock unless a real key is set."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return _mock_generate(query, chunks), "mock"
    try:  # pragma: no cover - only runs with a real key
        import anthropic

        client = anthropic.Anthropic(api_key=api_key)
        resp = client.messages.create(
            model="claude-opus-4-8",
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": _build_prompt(query, chunks)}],
        )
        text = next((b.text for b in resp.content if b.type == "text"), "")
        return text, "claude-opus-4-8"
    except Exception as exc:  # never crash the endpoint on a provider error
        return _mock_generate(query, chunks) + f" (LLM error: {exc})", "mock-fallback"


def answer(conn, query: str, user_clearance: int, k: int = 3) -> dict[str, Any]:
    """End-to-end: retrieve -> generate -> return answer with citations."""
    chunks = retrieve(conn, query, user_clearance=user_clearance, k=k)
    text, generator = generate(query, chunks)
    citations = [{"n": i + 1, "source": c["source"]} for i, c in enumerate(chunks)]
    return {"answer": text, "generator": generator,
            "citations": citations, "retrieved": len(chunks)}
