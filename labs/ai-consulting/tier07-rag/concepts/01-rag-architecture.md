# Concepts: RAG Architecture

**Read this before you touch the keyboard.** Tier 7 is the flagship enterprise tier: you build a Retrieval-Augmented Generation (RAG) system a company would actually deploy. RAG is the single most-requested AI-consulting deliverable right now, because it lets a company answer questions from its own private documents using an LLM, without retraining the model and without leaking those documents into a public API's training data.

You already think in data, sets, and SQL. RAG is, at its heart, a database problem wearing an AI hat: store documents so you can find the right ones fast, then hand those to a language model to write the answer. Everything in this tier maps to code you will write in Project 7.

---

## 1. What problem RAG solves

A large language model (LLM) like Claude knows a lot, but it does not know:

- Your company's internal wiki, contracts, runbooks, or HR policies.
- Anything created after its training cutoff.
- Which facts are true for *your* organization specifically.

If you just ask the model "what is our refund policy", it will either say "I don't know" or - worse - **make something up** (this is called a *hallucination*). Neither is acceptable for a business.

Two ways to fix this:

- **Fine-tuning** - retrain the model on your documents. Expensive, slow, has to be redone every time a document changes, and still hallucinates.
- **RAG** - keep the model as-is, but at question time, *retrieve* the relevant documents and paste them into the prompt as context. The model answers from what you gave it. Cheap, updates instantly when a document changes, and you can show *which* document each fact came from (a citation).

RAG wins for almost every enterprise knowledge use case. That is why you are learning it.

---

## 2. The mental model: open-book exam

Think of the LLM as a smart student taking an **open-book exam**.

- **Closed book** (no RAG): the student answers from memory. Confident, fast, sometimes wrong.
- **Open book** (RAG): before answering, the student looks up the relevant page and answers from it. Slower, but grounded in the actual text - and can cite the page.

Your job as the RAG engineer is to be the librarian who hands the student *the right pages, and only the right pages*, fast. If you hand over the wrong pages, the student writes a confident wrong answer. Retrieval quality is everything.

---

## 3. The 14-step RAG pipeline

Real RAG is not two steps ("search, then generate"). It is a pipeline. Here are the 14 stages every production RAG system has, split into two phases: **ingestion** (done once, ahead of time) and **query** (done per question).

### Ingestion (offline, done when documents change)

1. **Collection** - gather the source documents (PDFs, Word docs, wiki pages, spreadsheets). Track where each came from and who is allowed to see it.
2. **Parsing** - turn each file into plain text. A PDF is not text - it is a layout; you have to extract the words.
3. **Cleaning** - strip headers, footers, page numbers, boilerplate, and junk that would pollute retrieval.
4. **Chunking** - split each document into smaller pieces (chunks) of a few hundred words. You retrieve *chunks*, not whole documents, because a whole document is too big to paste into a prompt and too coarse to match a specific question.
5. **Metadata** - attach data to each chunk: source filename, page number, document owner, access level, language, version, date. This is what powers filtering and citations later.
6. **Embedding** - convert each chunk's text into a vector (a list of numbers) that captures its meaning. See [02-embeddings.md](02-embeddings.md).
7. **Vector storage** - store the chunks and their vectors in a database that can search by vector similarity (you will use PostgreSQL with the pgvector extension). See [03-vector-databases.md](03-vector-databases.md).

### Query (online, done per user question)

8. **Retrieval** - embed the user's question the same way, then find the chunks whose vectors are closest to it. These are your candidate answers.
9. **Reranking** - optionally re-score the top candidates with a more precise (slower) method, so the very best chunks rise to the top.
10. **Prompt construction** - assemble a prompt: the retrieved chunks as context, the user's question, and instructions like "answer only from the context; cite your sources; if the answer is not in the context, say you do not know".
11. **Generation** - send that prompt to the LLM and get an answer. See the BUILD guide for how to call Claude (and how to run a mock generator with no key).
12. **Citation** - report which chunks the answer came from, so the user can verify it.
13. **Evaluation** - measure whether the system is any good: is the retrieved context relevant, is the answer grounded in it, are the citations correct? See [05-rag-evaluation.md](05-rag-evaluation.md).
14. **Monitoring** - in production, watch latency, cost, error rate, and answer quality over time, so you notice when something degrades (like an embedding-model change silently breaking retrieval - which is one of your SURVIVE scenarios).

You will build every one of these stages in Project 7.

---

## 4. Where RAG goes wrong (the consultant's checklist)

Most of your value as a consultant is knowing the failure modes before they happen:

- **Bad retrieval** - the model gets the wrong chunks, so even a perfect LLM writes a wrong answer. Usually a chunking or embedding problem.
- **Hallucination despite context** - the model ignores the context and answers from memory. Fixed with a strict prompt ("answer *only* from the context") and by measuring groundedness.
- **Access-control leaks** - the system retrieves a chunk the user is not allowed to see. This is a **security incident**, not a quality bug. Enterprise RAG lives or dies on getting this right - it is your most important SURVIVE scenario.
- **Stale index** - a document changed but the index still has the old version. Fixed with re-ingestion and versioning.
- **Silent embedding drift** - someone swaps the embedding model, but the old vectors were made with the old model, so new questions no longer match. Retrieval quietly gets worse and no error is thrown. Also a SURVIVE scenario.

---

## 5. Why this stack (Postgres + pgvector + Claude)

- **PostgreSQL + pgvector** - you already know Postgres. pgvector adds a `vector` column type and similarity search, so you get vector search, metadata filtering (plain SQL `WHERE`), and access control (also SQL `WHERE`) in one database you already trust. No separate vector database to run. This is the pragmatic enterprise choice.
- **Claude** (via the Anthropic API) - the generation model. In the BUILD you will call it with an API key when you have one, and fall back to a **mock generator** when you do not, so the whole system runs and can be tested offline on a small CPU box.
- **A small CPU embedding model** (or a deterministic hashing fallback) - so embedding also runs offline, with no GPU and no paid API.

The point of this stack: the entire pipeline runs on one modest Linux box, offline, for free, and every piece maps to a real production choice. That is exactly what makes it a credible consulting demo.

Next: [02-embeddings.md](02-embeddings.md).

---

## References

Authoritative sources for the concepts in this document. Model names, versions, and prices change - reconfirm current details before quoting them to a client.

- Retrieval-Augmented Generation, original paper (Lewis et al., 2020): https://arxiv.org/abs/2005.11401
- pgvector (vector storage and similarity search in PostgreSQL): https://github.com/pgvector/pgvector
- Anthropic API / Claude docs (the generation model in this stack): https://docs.anthropic.com/ (model IDs and pricing change - always use the current values from the docs)
- sentence-transformers (the small CPU embedding model option): https://sbert.net/
