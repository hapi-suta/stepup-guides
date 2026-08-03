"""Tests for Project 7. The pure-logic tests need no database and run fast.
The DB-backed tests require the schema loaded, corpus ingested, and users
seeded (they skip cleanly if the database is unreachable).

Run:  python -m pytest -q
"""

from __future__ import annotations

import pytest

import rag


# ---- Pure logic (no DB) ----------------------------------------------------

def test_embed_is_deterministic():
    a = rag.embed("password reset")
    b = rag.embed("password reset")
    assert a == b
    assert len(a) == rag.EMBED_DIM


def test_embed_similar_texts_closer_than_unrelated():
    # cosine distance: smaller = more similar
    def cos_dist(x, y):
        dot = sum(i * j for i, j in zip(x, y))
        return 1 - dot  # vectors are already L2-normalised
    q = rag.embed("how do I reset my password")
    near = rag.embed("I forgot my login password")
    far = rag.embed("what time does the cafeteria open")
    assert cos_dist(q, near) < cos_dist(q, far)


def test_chunk_text_respects_max_and_is_nonempty():
    text = "\n\n".join(f"Paragraph number {i} has some words in it." for i in range(20))
    chunks = rag.chunk_text(text, max_chars=200, overlap_chars=20)
    assert len(chunks) > 1
    assert all(c.strip() for c in chunks)
    assert all(len(c) <= 300 for c in chunks)  # max + overlap headroom


def test_chunk_text_empty():
    assert rag.chunk_text("") == []
    assert rag.chunk_text("   \n\n  ") == []


def test_build_prompt_numbers_and_cites():
    chunks = [
        {"source": "a.txt", "chunk_text": "Alpha fact."},
        {"source": "b.txt", "chunk_text": "Beta fact."},
    ]
    prompt = rag.build_prompt("q?", chunks)
    assert "[1]" in prompt and "[2]" in prompt
    assert "Alpha fact." in prompt


def test_mock_generate_refuses_without_context():
    out = rag._mock_generate("anything", [])
    assert "don't have that information" in out.lower()


def test_mock_generate_grounds_and_cites():
    chunks = [{"source": "x.txt", "chunk_text": "The probation period is ninety days.",
               "page": 1, "access_level": 1, "lang": "en"}]
    out = rag._mock_generate("probation?", chunks)
    assert "ninety" in out.lower()
    assert "[1]" in out


# ---- DB-backed (skip if DB unreachable) ------------------------------------

@pytest.fixture(scope="module")
def conn():
    try:
        c = rag.db_conn()
    except Exception:
        pytest.skip("database not reachable")
    yield c
    c.close()


def _has_chunks(conn) -> bool:
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM chunks")
        return cur.fetchone()[0] > 0


def test_retrieval_returns_relevant_chunk(conn):
    if not _has_chunks(conn):
        pytest.skip("corpus not ingested")
    rows = rag.retrieve(conn, "remote work probation period", user_level=1, k=3)
    assert rows, "expected at least one chunk"
    assert any("en-remote-work.txt" == r["source"] for r in rows)


def test_access_control_blocks_restricted_doc(conn):
    """CRITICAL: a level-1 user must NEVER retrieve the restricted exec-comp doc."""
    if not _has_chunks(conn):
        pytest.skip("corpus not ingested")
    rows = rag.retrieve(conn, "CEO salary band executive compensation", user_level=1, k=10)
    assert all(r["access_level"] <= 1 for r in rows)
    assert not any(r["source"] == "en-exec-comp.txt" for r in rows), \
        "SECURITY LEAK: restricted document retrieved for a low-clearance user"


def test_access_control_allows_authorized_user(conn):
    if not _has_chunks(conn):
        pytest.skip("corpus not ingested")
    rows = rag.retrieve(conn, "CEO salary band executive compensation", user_level=4, k=10)
    assert any(r["source"] == "en-exec-comp.txt" for r in rows), \
        "authorized (level 4) user should be able to retrieve the restricted doc"
