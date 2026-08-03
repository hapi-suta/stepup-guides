# Interview: RAG Systems

These questions test whether you can design, build, and debug RAG systems in production - not just explain the concept.

---

## Question 1: RAG Architecture

**Q: Walk me through how you'd design a RAG system for a team of 50 DBAs who need to query 10,000 pages of internal runbooks. What are your key design decisions?**

**Model Answer:**

The architecture has four layers: ingestion, storage, retrieval, and generation.

**Ingestion:** Parse the 10,000 pages from markdown/PDF. Chunk by section headers since runbooks are structured. Target 100-200 words per chunk. Add metadata: source file, section title, last_modified date, database engine (PostgreSQL, MySQL, etc.), category (backup, monitoring, troubleshooting). Estimate: ~50,000 chunks total.

**Storage:** pgvector in PostgreSQL. Single table with content, embedding (1536-dim if using OpenAI, 384 if using local models), source, metadata JSONB. HNSW index for fast search. At 50K chunks with 1536-dim embeddings, that's ~300MB of vector data - easily fits on one PostgreSQL instance.

**Retrieval:** Hybrid search - combine vector similarity (semantic) with full-text search (keyword). Weight: 0.7 vector + 0.3 full-text. Add metadata filters: if the user asks about MySQL, only search MySQL docs. Retrieve top 5 chunks. Apply a similarity threshold (0.3) to filter out noise.

**Generation:** Claude with a system prompt that enforces: use only provided context, cite sources, say "I don't know" when context is insufficient. Temperature 0 for consistency. Max 500 tokens.

**Key decisions:**
- pgvector over Pinecone: team already runs PostgreSQL, no need for another service
- Local embeddings (all-MiniLM-L6-v2) over OpenAI: no per-call cost for embedding, data stays internal
- Hybrid search over pure vector: runbooks contain exact commands and config keys that benefit from keyword matching
- Source citation is mandatory: DBAs need to verify advice against the original runbook before acting

**Scaling concerns:** 50K chunks is small. pgvector handles this on a single node. If it grows to 5M+, consider partitioning by engine or using Pinecone.

**Key points to hit:**
- End-to-end architecture (ingest, store, retrieve, generate)
- Chunk strategy matched to document type
- Hybrid search for keyword + semantic
- Metadata filtering to narrow results
- pgvector sizing reasoning
- Source citation for trust

---

## Question 2: Chunking Strategy

**Q: You have a 200-page PostgreSQL operations manual. How do you chunk it for RAG, and how do you know if your chunking is good?**

**Model Answer:**

**Chunking approach for structured technical docs:**

First, parse the document structure. Operations manuals have chapters, sections, subsections. I'd chunk at the section level (## headers in markdown) because each section typically covers one topic.

**Rules:**
- Split on section headers
- Minimum chunk: 30 words (merge with neighbor if smaller)
- Maximum chunk: 300 words (split on paragraph boundaries if larger)
- Never split inside code blocks
- Preserve the section header in the chunk (gives embedding context)
- Add parent header as prefix ("Chapter 5: Backup > Section 5.3: WAL Archiving")

**For a 200-page manual, I'd expect:**
- ~100 sections at ~200 words average = ~100 chunks
- Plus some splits for long sections = ~130-150 total chunks
- At 384 dimensions, that's ~0.2MB of vectors - trivial for pgvector

**Evaluating chunk quality:**

Build a test set of 20 question-answer pairs where I know the correct source section. Then measure:

1. **Retrieval precision@3:** What fraction of top-3 results contain the right chunk? Target: >80%.
2. **Discrimination gap:** The similarity score difference between the best match and second-best match. If the gap is < 0.05, chunks are too similar (overlapping topics).
3. **Coverage:** Are there questions where NO chunk scores above the threshold? If yes, there's a content gap.

If precision is below 80%, I'd try:
- Smaller chunks (maybe sections are too broad)
- Adding a title/keywords prefix to each chunk
- Hybrid search (add full-text to catch exact terms)

**Key points to hit:**
- Chunk strategy based on document structure
- Concrete size bounds with reasoning
- Code block preservation
- Header context preservation
- Quantitative evaluation method
- Iterative improvement approach

---

## Question 3: Embedding Model Selection

**Q: When would you use a local embedding model vs the OpenAI embedding API?**

**Model Answer:**

**Local model (e.g., all-MiniLM-L6-v2, 384 dims):**
- Zero per-call cost. Embed 100K documents for free.
- Data never leaves your network. Critical for sensitive internal docs.
- ~500 docs/sec on Apple Silicon. Fast enough for batch and real-time.
- Lower dimensionality (384) means less storage and faster search.
- Quality is good but not best-in-class.

**OpenAI API (text-embedding-3-small, 1536 dims):**
- Higher quality embeddings, especially for nuanced queries.
- 1536 dimensions capture more semantic detail.
- $0.02 per 1M tokens (~$0.20 to embed 10K documents). Cheap.
- Requires internet, adds latency (~100ms per call).
- Data goes to OpenAI's servers.

**My decision framework:**
1. Start with local (all-MiniLM-L6-v2). It's free, fast, and private.
2. Measure retrieval quality with a test set.
3. If accuracy is below 80%, try OpenAI embeddings on the SAME test set.
4. If OpenAI is noticeably better, use it for production.
5. For sensitive data (internal configs, credentials, incident reports): always local.

**Common mistake:** People default to OpenAI because it's "better." For most RAG use cases with well-chunked technical docs, local models perform within 5% of OpenAI. That 5% rarely justifies the cost and privacy tradeoff.

**Advanced option:** Use a local model for initial embedding + search, then use a cross-encoder (more expensive but more accurate) to re-rank the top 10 results. Best of both worlds.

**Key points to hit:**
- Cost comparison (free vs per-token)
- Privacy/data residency consideration
- Quality difference is smaller than expected for technical docs
- Measure before choosing
- Cross-encoder re-ranking as a middle ground

---

## Question 4: RAG Failure Modes

**Q: Your RAG system is returning correct documents but generating wrong answers. How do you debug this?**

**Model Answer:**

If retrieval is good but generation is bad, the problem is in the prompt or the model's handling of context. I'd debug systematically:

**Step 1: Inspect the full prompt.** Print the exact prompt being sent to the model - system prompt, retrieved context, and user question. Read it yourself. Is the context actually relevant? Is it too long for the model to focus?

**Step 2: Check context window stuffing.** If you're feeding 5 long chunks (2000 tokens each) plus a system prompt, that's 10K+ tokens of context. The model may lose focus on the relevant chunk. Fix: reduce to top 3 chunks, or put the most relevant chunk last (recency bias).

**Step 3: Test the prompt without RAG.** Send the same question to Claude with the context copy-pasted manually. If Claude gives a good answer, the problem is in how your code builds the prompt (maybe context is being truncated or formatted badly).

**Step 4: Check for conflicting information.** Two retrieved chunks might contradict each other (one outdated, one current). The model averages them and produces nonsense. Fix: add dates to metadata, prefer newer documents, or add a rule: "If documents conflict, use the most recently updated one."

**Step 5: Strengthen the system prompt.** Common fixes:
- "Answer ONLY from the provided context" (prevents hallucination)
- "If documents conflict, say so" (surfaces contradictions)
- "Quote the relevant passage before answering" (forces grounding)
- "If you're not confident, say what's missing" (prevents confabulation)

**Step 6: Check temperature.** Temperature > 0 introduces randomness. For factual RAG, always use temperature = 0.

**The most common cause** in my experience: the context is too long and the answer is buried in the middle. Models attend less to middle content ("lost in the middle" problem). Fix: put the highest-similarity chunk at the end of the context, right before the question.

**Key points to hit:**
- Systematic debugging approach (inspect prompt first)
- Context window stuffing problem
- "Lost in the middle" phenomenon
- Conflicting documents
- Temperature must be 0 for factual RAG
- Manual testing without RAG to isolate the problem

---

## Question 5: pgvector vs Dedicated Vector Databases

**Q: A colleague argues you should use Pinecone instead of pgvector. When are they right and when are they wrong?**

**Model Answer:**

**pgvector wins when:**
- You already run PostgreSQL (no new infrastructure)
- Dataset is under 5 million vectors
- You need SQL joins, transactions, and metadata filtering in the same query
- Data sensitivity requires everything on your own infrastructure
- Your team knows PostgreSQL but doesn't know Pinecone
- You want one backup strategy, one monitoring stack, one set of permissions

**Pinecone wins when:**
- Dataset exceeds 10M+ vectors and growing
- You need sub-millisecond search at massive scale
- You don't have PostgreSQL expertise on the team
- You want zero-ops vector search (managed service)
- You need features like namespaces, sparse-dense hybrid search built-in
- Cost of managed service is less than ops cost of self-managing pgvector at scale

**The numbers:** pgvector with HNSW on a typical 8GB RAM machine handles 1-5M vectors with <50ms search time. That covers most enterprise RAG use cases. You need Pinecone when you're building a consumer product searching billions of embeddings.

**My recommendation:** Start with pgvector. Always. It's free, it's familiar, and it keeps your data in one place. Migrate to Pinecone when pgvector becomes a measurable bottleneck - not before. Premature infrastructure is the same mistake as premature optimization.

**The real answer:** The choice between pgvector and Pinecone is an infrastructure decision, not an AI decision. Make it based on ops burden, data volume, and team skills - not on which one sounds more "AI."

**Key points to hit:**
- pgvector for most use cases (under 5M vectors)
- Pinecone for massive scale or zero-ops requirement
- Decision based on data volume and ops, not hype
- Start simple, migrate when needed
- Integration advantage of pgvector (SQL joins, same backup, same monitoring)
