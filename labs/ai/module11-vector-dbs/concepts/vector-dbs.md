# Vector Databases Deep Dive - Concepts

Module 03 introduced RAG and vector search at a high level. This module goes deep - how vector indexes work, when to use each type, performance tuning, and production deployment patterns.

---

## Why Should You Care?

Every RAG system, semantic search engine, and recommendation system depends on fast vector similarity search. As a DBA, you'll be asked to:
- Set up and tune pgvector on your PostgreSQL clusters
- Choose between pgvector, Pinecone, Weaviate, or Qdrant
- Optimize vector index performance (it's not like B-tree tuning)
- Handle production issues: slow queries, high memory usage, stale embeddings

This is where your PostgreSQL expertise gives you an advantage. You already understand indexes, query plans, and performance tuning. Vector databases use the same concepts with different algorithms.

---

## The DBA Analogy

| PostgreSQL Concept | Vector DB Equivalent |
|-------------------|---------------------|
| B-tree index | HNSW index (hierarchical navigable small world) |
| GiST index | IVFFlat index (inverted file with flat quantization) |
| Sequential scan | Brute-force exact search |
| EXPLAIN ANALYZE | Recall@K measurement |
| Selectivity | Dimensionality and distance distribution |
| Index maintenance (REINDEX) | Rebuilding vector indexes after data changes |
| Partial index | Filtered vector search (WHERE clause + similarity) |
| Index-only scan | Storing vectors in the index vs fetching from heap |

---

## Key Concepts

### 1. Vector Similarity Search

Given a query vector, find the K most similar vectors in the database.

**Three distance metrics:**

| Metric | Formula | Use When |
|--------|---------|----------|
| Cosine distance | 1 - cos(angle) | Text embeddings (most common) |
| L2 (Euclidean) | sqrt(sum((a-b)^2)) | Image features, numeric data |
| Inner product | sum(a * b) | Normalized vectors, recommendations |

For text search with embeddings, cosine distance is almost always the right choice.

### 2. Exact vs Approximate Search

**Exact search (brute force):**
- Compare query against EVERY vector in the database
- 100% recall (never misses the true nearest neighbor)
- O(N) - linear time, slow for large datasets
- Like a sequential scan in PostgreSQL

**Approximate Nearest Neighbor (ANN):**
- Use an index to quickly find APPROXIMATELY nearest vectors
- 95-99% recall (might miss a few true neighbors)
- O(log N) - much faster for large datasets
- Like using a B-tree index - trade some accuracy for speed

### 3. Index Types

**IVFFlat (Inverted File with Flat storage):**
- Splits vectors into clusters (like partitioning a table)
- At query time, only searches nearby clusters
- Fast to build, moderate recall
- Tune with `nlist` (number of clusters) and `nprobe` (clusters to search)

**HNSW (Hierarchical Navigable Small World):**
- Builds a multi-layer graph connecting similar vectors
- Navigates the graph to find neighbors quickly
- Slower to build, higher recall, more memory
- Tune with `m` (connections per node) and `ef_construction`/`ef_search`

| | IVFFlat | HNSW |
|--|---------|------|
| Build speed | Fast | Slow |
| Query speed | Good | Excellent |
| Memory | Low | High |
| Recall | 90-95% | 97-99% |
| Best for | Large datasets, limited memory | Performance-critical, high accuracy |

### 4. pgvector - Vector Search in PostgreSQL

pgvector adds vector support directly to PostgreSQL:
- `vector` data type (stores embeddings)
- `<=>` operator (cosine distance)
- `<->` operator (L2 distance)
- `<#>` operator (inner product)
- IVFFLAT and HNSW indexes

**Why pgvector for DBAs:**
- No new infrastructure (runs in your existing PostgreSQL)
- Full SQL support (JOIN vectors with relational data)
- ACID transactions (vectors and metadata are consistent)
- Familiar tooling (pg_dump, pg_stat, EXPLAIN)

---

## What You'll Build

| Build | What | Why |
|-------|------|-----|
| 01 - pgvector Setup and Basics | Install, create tables, basic queries | Foundation for all vector operations |
| 02 - Vector Indexes | IVFFlat vs HNSW, tuning parameters | Performance optimization |
| 03 - Hybrid Search | Combine vector similarity with SQL filters | Real-world search patterns |
| 04 - Production Patterns | Batch operations, monitoring, maintenance | Run vector search in production |
