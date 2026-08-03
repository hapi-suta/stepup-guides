# USE 01: Vector DB Exercises

Practice what you built. Each exercise reinforces a concept from Builds 01-04.

---

## Exercise 1: Multi-Table Vector Search (Build 01)

Build a search system that spans multiple tables.

**Task:**
1. Create two tables: `runbooks` (title, content, team, embedding) and `incidents` (title, description, severity, embedding)
2. Insert 10 runbooks and 10 incidents with embeddings
3. Build a search function that searches BOTH tables and returns ranked results
4. Label each result with its source table (runbook or incident)
5. Test with: "database replication failure" (should find both runbooks and incidents)

---

## Exercise 2: Index Tuning Lab (Build 02)

Find the optimal index configuration for your data.

**Task:**
1. Create a table with 100,000 random 256-dimensional vectors
2. Build an IVFFlat index and measure recall@10 with nprobe = 1, 5, 10, 20, 50
3. Build an HNSW index and measure recall@10 with ef_search = 10, 20, 40, 80, 200
4. Print a comparison table: index type, parameter, query time, recall
5. Determine: which index gives 95% recall at the lowest query time?

**Hint:** Recall = intersection(approximate_results, exact_results) / K

---

## Exercise 3: RAG Pipeline with Hybrid Search (Build 03)

Build a complete RAG pipeline with hybrid search.

**Task:**
1. Create a `knowledge_base` table with 20 PostgreSQL documentation chunks
2. Implement three search methods: vector only, keyword only, hybrid (70/30)
3. For 5 test queries, compare all three methods
4. Print which method ranks the best result highest for each query
5. Calculate average rank of the best result across methods

**Expected outcome:** Hybrid search should rank the best result higher on average.

---

## Exercise 4: Embedding Freshness Monitor (Build 04)

Build a system that tracks embedding staleness.

**Task:**
1. Create a table with columns: content, embedding, embedding_model, embedding_updated_at
2. Insert 50 documents with embeddings
3. Simulate: update 10 documents' content WITHOUT updating embeddings
4. Build a `check_stale_embeddings()` function that finds documents where content changed after embedding_updated_at
5. Build a `refresh_stale_embeddings()` function that regenerates embeddings for stale documents
6. Print a report: total documents, stale count, freshness percentage

---

## Exercise 5: Production Vector Search System (All Builds)

Build a complete production-ready vector search system.

**Task:**
1. Create a schema with: documents table, HNSW index, GIN index for full-text
2. Implement hybrid search (vector + keyword + category filter)
3. Add similarity threshold (only return results > 0.3 similarity)
4. Implement batch insert using COPY
5. Add monitoring queries: table size, index size, dead tuple count
6. Add embedding freshness tracking
7. Write a search API function that accepts: query text, category filter (optional), min_similarity, limit
8. Test with 10 queries and print results

---

## Scoring Guide

| Exercise | Skill Tested | Difficulty |
|----------|-------------|------------|
| 1 | Multi-table vector search | Beginner |
| 2 | Index tuning and recall measurement | Intermediate |
| 3 | Hybrid search implementation | Intermediate |
| 4 | Embedding maintenance | Intermediate |
| 5 | Production vector search system | Advanced |
