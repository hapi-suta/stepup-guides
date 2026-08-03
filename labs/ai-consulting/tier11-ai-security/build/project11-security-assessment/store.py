"""A tiny 'vector' store for the mock knowledge assistant.

To keep the tier free and dependency-light, retrieval is keyword overlap, not
real embeddings - but the security properties are identical: untrusted document
text gets retrieved and fed to the model, so a poisoned or injected document can
hijack the assistant. Documents live in a JSON file so a SURVIVE scenario can
inject a malicious one and you can inspect/quarantine it.

Each document is: {"id", "source", "text", "trusted"}. The 'trusted' flag is
NOT enforced by default - the undefended assistant retrieves everything. Adding
enforcement is part of the remediation you will do.
"""
import json
import os
import re

DEFAULT_DB = os.path.join(os.path.dirname(__file__), "knowledge.json")


def _tokenize(text: str) -> set:
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def load(db_path: str = DEFAULT_DB) -> list:
    if not os.path.exists(db_path):
        return []
    with open(db_path, encoding="utf-8") as fh:
        return json.load(fh)


def save(docs: list, db_path: str = DEFAULT_DB) -> None:
    with open(db_path, "w", encoding="utf-8") as fh:
        json.dump(docs, fh, indent=2)


def retrieve(query: str, k: int = 3, db_path: str = DEFAULT_DB) -> list:
    """Return the top-k documents by keyword overlap with the query."""
    docs = load(db_path)
    q = _tokenize(query)
    scored = []
    for doc in docs:
        overlap = len(q & _tokenize(doc.get("text", "")))
        scored.append((overlap, doc))
    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [doc for score, doc in scored[:k] if score > 0] or [d for _, d in scored[:k]]
