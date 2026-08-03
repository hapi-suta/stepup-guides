# Concepts: RAG Evaluation

"It seems to work" is not a deliverable. A consultant proves a RAG system is good with numbers. Evaluation is what turns a demo into something a client will trust in production. This maps directly to USE exercise 1 (the eval harness) and to the monitoring endpoint in Project 7.

---

## 1. Why you must evaluate

RAG has two places to go wrong - retrieval and generation - and a failure in either produces a confident wrong answer. Without measurement you cannot tell:

- whether a change (new chunker, new embedding model, new prompt) made things better or worse,
- whether the system is safe to ship,
- where to spend effort (fixing retrieval vs fixing the prompt).

You measure against a **golden set**: a hand-built list of questions, each with the expected answer and, ideally, which document(s) should be retrieved. Project 7 ships a small golden set; your eval harness scores the system against it.

---

## 2. Retrieval metrics - did we fetch the right chunks?

Retrieval is a search problem, so you use search metrics. For a question whose correct source chunks are known:

- **Precision@k** - of the top *k* chunks retrieved, what fraction are actually relevant? (Did we retrieve junk?)
- **Recall@k** - of all the relevant chunks that exist, what fraction did we retrieve in the top *k*? (Did we miss the good one?)
- **MRR** (Mean Reciprocal Rank) - how high up did the *first* relevant chunk land, averaged across questions? Rewards putting a good chunk at position 1 rather than position 5.
- **NDCG** (Normalized Discounted Cumulative Gain) - a rank-aware score that credits relevant chunks more when they appear near the top. Use it when *ordering* within the top *k* matters, not just membership.
- **Context relevance / context precision** - a broader judgement: how on-topic is the retrieved context as a whole? In the Ragas framework this is `context_precision` (are the retrieved contexts relevant and well-ranked) paired with `context_recall` (did retrieval bring back all the information the answer needs). See section 5 for how these are scored.

If retrieval recall is low, the right chunk never reaches the LLM and no prompt tweak can fix the answer - fix retrieval first (chunking, embeddings, hybrid search).

---

## 3. Generation metrics - was the answer good, given the context?

Assuming retrieval fetched the right context, judge the answer:

- **Answer relevance** - does the answer actually address the question asked? (In the Ragas framework this is `answer_relevancy`, also called response relevancy.)
- **Groundedness (faithfulness)** - is every claim in the answer supported by the retrieved context, with nothing invented? This is the anti-hallucination metric and the single most important one for enterprise trust. An answer can be relevant *and* ungrounded (it addresses the question but made the facts up). Ragas calls this `faithfulness` and computes it as the fraction of the answer's claims that are supported by the retrieved context (see: docs.ragas.io).
- **Citation accuracy** - do the sources the answer cites actually contain the claims attributed to them? A citation that points to the wrong chunk is worse than no citation - it manufactures false confidence.
- **Unsupported-claim rate** - the flip side of groundedness: what fraction of the answer's statements have no support in the context? You want this near zero.

**Groundedness and citation accuracy are the two you will actually compute in USE exercise 1**, because they are the ones enterprises care about most and the ones you can score without a human in the loop.

---

## 4. Refusal quality - knowing when to say "I don't know"

A good RAG system **refuses** when the answer is not in the retrieved context, instead of guessing. So you must also test the *negative* cases:

- Ask a question the corpus cannot answer. A good system says "I don't have that information," and does **not** invent an answer.
- **Refusal quality** = does it refuse when it should (no context) *and* answer when it should (context present)? A system that refuses everything is useless; one that answers everything hallucinates. You want it calibrated.

Include unanswerable questions in your golden set on purpose, and check the system refuses them.

---

## 5. How to score without a human: the LLM-as-judge (and the mock)

You cannot hand-grade every answer on every run. Two automatable approaches:

- **Exact/keyword checks** - does the answer contain the expected key fact? Cheap and deterministic; good for factual golden questions. This is what the mock-runnable eval uses so it works with no API key.
- **LLM-as-judge** - ask a second LLM call "here is the context, the question, and the answer; is every claim in the answer supported by the context? score 0-1." Powerful but needs an API key and costs money.

Project 7's eval harness does groundedness and citation scoring with **deterministic checks** by default (so it runs and is testable offline with the mock generator), and can optionally use an LLM judge when a key is present. Flag clearly in your report which mode you ran.

---

## 6. Operational metrics - latency and cost

Quality is not the only axis a client cares about:

- **Latency** - end-to-end time per question (embedding + retrieval + generation). Retrieval is usually fast; generation dominates. Track p50 and p95, not just the average.
- **Cost** - per-question cost is driven by how many tokens you paste into the prompt (retrieved context) times the model's input price, plus output tokens. Retrieving fewer, better chunks lowers both latency and cost - another reason retrieval quality matters commercially.

Your Project 7 monitoring endpoint exposes these: number of queries, average latency, refusal rate, and error count - the operational health a production owner watches.

---

## 7. Monitoring in production

Evaluation is done before shipping; **monitoring** is continuous, after shipping. In production you watch for drift:

- A rising refusal rate can mean the index went stale or an embedding-model change broke retrieval (your `embedding-version-change` scenario).
- Rising latency or cost can mean chunks got bigger or retrieval is returning too many.
- Any spike in errors.

Wire a `/metrics` (or `/health`) endpoint that reports these, so an operator - or an alerting system - can see the system's health at a glance. A RAG system without monitoring is one silent regression away from quietly serving wrong answers, and no one will know until a user complains.

That completes the concepts. Now build it: [../build/01-project7-enterprise-knowledge-assistant.md](../build/01-project7-enterprise-knowledge-assistant.md).

---

## References

Authoritative sources used to fact-check this document. Framework metric names and defaults change - reconfirm before quoting specifics to a client.

- Ragas metrics (faithfulness, answer_relevancy, context_precision, context_recall, LLM-as-judge): https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/
- Retrieval metric definitions (Precision@k, Recall@k, MRR, NDCG): standard information-retrieval references; Ragas context-precision uses the precision@k formula - https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/context_precision/
- Latency percentiles (p50 / p95 / p99, why not the average): https://redis.io/blog/p95-latency/
