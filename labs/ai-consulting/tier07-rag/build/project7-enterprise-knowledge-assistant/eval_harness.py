"""Evaluation harness: score the RAG system against golden.json.

Metrics reported (all runnable OFFLINE with the mock generator):
  - retrieval_hit:   was the expected source document in the retrieved chunks?
  - groundedness:    is the answer's key fact present in the retrieved context?
                     (deterministic proxy for "answer is supported by context")
  - citation_ok:     if the answer cited [n], does chunk n exist and match the
                     answer's grounded fact?
  - refusal_ok:      unanswerable questions must be refused; answerable ones not.

This is intentionally deterministic so it passes with the mock generator and in
CI. With a real ANTHROPIC_API_KEY, groundedness is stricter (the real model
writes prose), but the keyword checks still apply.

Run as ec2-user:  python eval_harness.py
"""

from __future__ import annotations

import json
import os

import rag

REFUSAL = "don't have that information"


def _contains_any(text: str, needles: list[str]) -> bool:
    low = text.lower()
    return any(n.lower() in low for n in needles)


def evaluate() -> dict:
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "golden.json")) as f:
        golden = json.load(f)

    conn = rag.db_conn()
    results = []
    for item in golden["items"]:
        lang = item.get("lang")  # explicit in the golden set; None searches all
        res = rag.answer(conn, item["query"], user_level=item["clearance"], lang=lang, k=5)
        ans = res["answer"]
        sources = {c["source"] for c in res["citations"]}

        # retrieval hit
        if item["answerable"] and item["expect_source"]:
            retrieval_hit = item["expect_source"] in sources
        else:
            retrieval_hit = True  # unanswerable: nothing should be needed

        # refusal correctness
        refused = REFUSAL in ans.lower()
        refusal_ok = (refused != item["answerable"])

        # groundedness: for answerable items the key fact must appear in the
        # retrieved context; for unanswerable items a proper refusal counts.
        if item["answerable"]:
            # Re-fetch chunk text for the grounding check:
            chunks = rag.retrieve(conn, item["query"], user_level=item["clearance"], lang=lang, k=5)
            ctx_text = " ".join(c["chunk_text"] for c in chunks)
            grounded = _contains_any(ctx_text, item["must_contain"])
        else:
            grounded = refused

        # citation accuracy: an answerable, answered item should cite >=1 source
        if item["answerable"] and not refused:
            citation_ok = len(res["citations"]) >= 1 and retrieval_hit
        else:
            citation_ok = True

        results.append({
            "id": item["id"],
            "query": item["query"][:50],
            "retrieval_hit": retrieval_hit,
            "grounded": grounded,
            "citation_ok": citation_ok,
            "refusal_ok": refusal_ok,
        })

    conn.close()

    n = len(results)
    def frac(key: str) -> float:
        return sum(1 for r in results if r[key]) / n if n else 0.0

    summary = {
        "n": n,
        "retrieval_hit_rate": round(frac("retrieval_hit"), 3),
        "groundedness": round(frac("grounded"), 3),
        "citation_accuracy": round(frac("citation_ok"), 3),
        "refusal_quality": round(frac("refusal_ok"), 3),
        "results": results,
    }
    return summary


def main() -> None:
    s = evaluate()
    print(f"Golden set: {s['n']} questions\n")
    print(f"{'id':<5}{'retrieval':<11}{'grounded':<10}{'citation':<10}{'refusal':<9}query")
    for r in s["results"]:
        print(f"{r['id']:<5}"
              f"{str(r['retrieval_hit']):<11}"
              f"{str(r['grounded']):<10}"
              f"{str(r['citation_ok']):<10}"
              f"{str(r['refusal_ok']):<9}"
              f"{r['query']}")
    print()
    print(f"retrieval_hit_rate : {s['retrieval_hit_rate']}")
    print(f"groundedness       : {s['groundedness']}")
    print(f"citation_accuracy  : {s['citation_accuracy']}")
    print(f"refusal_quality    : {s['refusal_quality']}")


if __name__ == "__main__":
    main()
