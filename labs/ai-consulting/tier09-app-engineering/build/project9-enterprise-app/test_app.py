"""Tests for Project 9 that need NO database and NO API key.

These cover the pure logic that must never regress: the worker's chunker and
the retrieval keyword/mock-generation path. Database-backed behaviour (auth,
admin gating) is exercised in the BUILD guide with real HTTP calls, because it
needs the seeded database.

Run:  python -m pytest -q
"""
from __future__ import annotations

import retrieval
import worker


def test_chunker_splits_on_blank_lines():
    text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
    chunks = worker.chunk_text(text, max_chars=25)
    assert len(chunks) >= 2
    assert all(c.strip() for c in chunks)


def test_chunker_empty_returns_nothing():
    assert worker.chunk_text("") == []
    assert worker.chunk_text("   \n\n  ") == []


def test_mock_generate_refuses_without_context():
    # No chunks -> the assistant must refuse, not invent an answer.
    text, name = retrieval.generate("anything", [])
    assert text == "I don't have that information."
    assert name == "mock"


def test_mock_generate_cites_context():
    chunks = [{"chunk_text": "Meals are capped at 40 dollars per day.",
               "source": "expense-policy.txt"}]
    text, name = retrieval.generate("what is the meal cap?", chunks)
    assert "[1]" in text            # it cites the passage
    assert name == "mock"           # offline path, no key needed


def test_tokens_are_lowercased_words():
    assert retrieval._tokens("Hello, WORLD 42!") == {"hello", "world", "42"}
