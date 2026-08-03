# Interview 01: Vector Database Questions

Five questions you might get in an interview about vector databases and similarity search.

---

## Question 1: Explain How Vector Search Works

**Question:** How does vector similarity search find relevant documents, and how is it different from traditional text search?

**Strong answer:**

**Vector search converts text to numbers (embeddings), then finds the closest numbers.**

1. **Embedding:** Each document is converted to a vector (list of numbers, typically 384-1536 dimensions) using a model like BERT or all-MiniLM. These vectors capture MEANING, not just keywords.

2. **Indexing:** Vectors are stored with an index (HNSW or IVFFlat) that enables fast approximate nearest neighbor search.

3. **Query:** The search query is also converted to a vector. The database finds the K vectors closest to the query vector using a distance metric (usually cosine distance).

**Key difference from traditional search:**
- Keyword search: "database replication" only matches documents containing those exact words
- Vector search: "database replication" also matches "PostgreSQL standby synchronization" because they have similar MEANING

**When each is better:**
- Keyword search: exact terms matter (error codes, function names, "pg_stat_replication")
- Vector search: meaning matters (user asks questions in natural language)
- Hybrid search: combine both for the best results (70% vector + 30% keyword)

---

## Question 2: IVFFlat vs HNSW - When to Use Each?

**Question:** pgvector supports IVFFlat and HNSW indexes. Compare them and explain when you'd choose each.

**Strong answer:**

| Factor | IVFFlat | HNSW |
|--------|---------|------|
| Algorithm | Cluster-based (like table partitions) | Graph-based (like a B-tree for vectors) |
| Build speed | Fast (seconds for 1M vectors) | Slow (minutes for 1M vectors) |
| Query speed | Good | Excellent |
| Recall@10 | 90-95% with tuning | 97-99% |
| Memory | Low | 2-3x higher |
| Incremental inserts | Requires REINDEX | Supports them natively |

**When to choose IVFFlat:**
- Limited memory (vectors are large; HNSW doubles the memory)
- Large datasets (> 10M vectors) where HNSW build time is too long
- Data that's loaded in batches (REINDEX after each batch)
- Cost-sensitive environments

**When to choose HNSW:**
- Performance-critical applications (sub-millisecond queries)
- High recall requirements (can't afford to miss results)
- Data with frequent inserts/updates
- RAG systems where result quality directly impacts user experience

**Tuning rules of thumb:**
- IVFFlat: `lists = sqrt(n_rows)`, `probes = sqrt(lists)`
- HNSW: `m = 16` (default), `ef_construction = 128-256`, `ef_search = 40-100`

**My default:** Start with HNSW unless memory is a constraint. The recall advantage is worth the extra memory for most use cases.

---

## Question 3: pgvector vs Dedicated Vector Databases

**Question:** Why would you use pgvector instead of Pinecone, Weaviate, or Qdrant?

**Strong answer:**

**pgvector: use your existing PostgreSQL. Dedicated: purpose-built for vectors.**

**Choose pgvector when:**
- You already have PostgreSQL in your stack (no new infrastructure)
- You need JOIN vectors with relational data (vector search + SQL filters)
- You need ACID transactions (vectors and metadata must be consistent)
- Dataset is < 10M vectors
- Your team knows PostgreSQL (familiar tooling, monitoring, backups)
- You want one database, not two to maintain

**Choose a dedicated vector DB when:**
- Dataset exceeds 50M+ vectors
- You need distributed vector search across multiple nodes
- Vector search is your PRIMARY workload (not a feature of a larger app)
- You need advanced features: multi-tenancy, built-in reranking, auto-sharding
- You don't have PostgreSQL expertise on the team

**Specific trade-offs:**
- Pinecone: Fully managed, no infrastructure, but cloud-only and vendor lock-in
- Weaviate: Open source, good hybrid search, but another system to operate
- Qdrant: Open source, fast, good filtering, but another system to operate
- pgvector: Runs in PostgreSQL, familiar, but single-node and simpler feature set

**My recommendation for most DBA teams:** Start with pgvector. You get 90% of the functionality with zero new infrastructure. Only migrate to a dedicated vector DB if you hit specific limitations (scale, features, performance).

---

## Question 4: How Do You Handle Embedding Freshness?

**Question:** Your RAG knowledge base has 100,000 documents that get updated regularly. How do you keep embeddings in sync?

**Strong answer:**

**Track when content changes vs when embeddings were last generated.**

**Schema:**
```sql
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(384),
    content_updated_at TIMESTAMP,
    embedding_updated_at TIMESTAMP,
    embedding_model TEXT DEFAULT 'all-MiniLM-L6-v2'
);
```

**Three strategies:**

1. **Synchronous update (simple, slow writes):**
   - Trigger on UPDATE generates new embedding immediately
   - Pro: Always fresh
   - Con: Adds 50-200ms latency to every write

2. **Background refresh (recommended for production):**
   - Mark documents as stale when content changes
   - Background job processes stale documents in batches
   - Pro: Writes are fast, embeddings eventually consistent
   - Con: Brief staleness window (minutes to hours)

3. **Version-based refresh:**
   - Track embedding_model version
   - When model is upgraded, regenerate ALL embeddings
   - Pro: Ensures consistency after model changes
   - Con: Expensive for large datasets

**Monitoring:**
- Alert when stale percentage > 5%
- Track average staleness time
- Never mix embeddings from different models (cosine similarity is meaningless across models)

**My production setup:** Background refresh running every 15 minutes, processing up to 1,000 stale documents per run. Alert if stale > 5% for more than 1 hour.

---

## Question 5: Design a Production RAG Search System

**Question:** Design a search system for an internal PostgreSQL knowledge base with 50,000 documents. Walk me through the architecture.

**Strong answer:**

**Architecture:**

```
User Query
    |
    v
[1] Query Processing
    - Tokenize and embed the query
    - Extract keywords for hybrid search
    |
    v
[2] Hybrid Search (pgvector)
    - Vector similarity: embedding <=> query_embedding
    - Keyword match: ts_rank(search_vector, query)
    - Combined: 0.7 * vector + 0.3 * keyword
    - Filters: category, date range, similarity > 0.3
    |
    v
[3] Re-ranking (optional)
    - Cross-encoder re-ranks top 20 results
    - More accurate than bi-encoder but slower
    |
    v
[4] Return top 5 results
```

**PostgreSQL Schema:**
```sql
CREATE TABLE knowledge_base (
    id SERIAL PRIMARY KEY,
    title TEXT,
    content TEXT,
    category TEXT,
    embedding vector(384),
    search_vector tsvector,
    embedding_updated_at TIMESTAMP
);

CREATE INDEX idx_hnsw ON knowledge_base
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 128);

CREATE INDEX idx_fts ON knowledge_base USING gin(search_vector);
CREATE INDEX idx_category ON knowledge_base (category);
```

**Key decisions:**
1. **HNSW over IVFFlat:** 50K vectors is small enough for HNSW, and the recall advantage matters for search quality
2. **384-dim embeddings:** all-MiniLM-L6-v2 is fast and good quality for this scale
3. **Hybrid search:** Vector for meaning, keyword for exact terms like "pg_stat_replication"
4. **Similarity threshold:** 0.3 minimum prevents returning irrelevant results
5. **Background embedding refresh:** 15-minute cycle, alert if stale > 5%

**Monitoring:**
- Search latency P50/P95/P99
- Recall sampling: weekly exact vs approximate comparison
- Embedding staleness percentage
- Index size and table bloat
- User feedback: were results helpful? (for continuous improvement)
