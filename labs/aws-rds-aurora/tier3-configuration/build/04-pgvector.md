# BUILD 04 - pgvector

**Time:** 35 minutes
**Goal:** Install pgvector, store embeddings, run similarity searches, build indexes, and understand the difference between RDS and Aurora for vector workloads.

---

## Prerequisites

- RDS PostgreSQL 16 instance with psql access
- pgvector available in `pg_available_extensions` (verify in Part 1)

---

## What Is pgvector?

pgvector adds a `vector` data type to PostgreSQL. You use it to store and search mathematical representations of data - called embeddings - produced by AI/ML models.

An embedding is just an array of floating-point numbers. Two items that are "similar" have embeddings that are mathematically close to each other.

**Real-world uses:**
- Semantic search: "find articles similar to this one"
- Recommendation: "find products similar to what this user bought"
- Image search: "find images that look like this photo"
- RAG (Retrieval Augmented Generation): "find relevant documents to answer this question"

---

## Part 1 - Install pgvector

pgvector does not require preloading in `shared_preload_libraries`. You install it directly.

**Connect to your database:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d postgres
```

**Check that pgvector is available:**

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name = 'vector';
```

Expected output (yours will differ):
```
  name  | default_version | installed_version
--------+-----------------+-------------------
 vector | 0.7.0           |
(1 row)
```

**Install the extension:**

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

**Verify installation:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE name = 'vector';
```

Expected output (yours will differ):
```
  name  | installed_version
--------+-------------------
 vector | 0.7.0
(1 row)
```

---

## Part 2 - Create a Table with a Vector Column

Create a table that stores product embeddings. In a real system, these embeddings would come from an AI model like OpenAI's text-embedding-ada-002. For this lab, you will insert manually crafted vectors.

```sql
CREATE TABLE products (
  id        serial PRIMARY KEY,
  name      text NOT NULL,
  category  text,
  embedding vector(4)  -- 4 dimensions for this example; real embeddings are 1536 or more
);
```

The `vector(4)` type declaration says each embedding has exactly 4 dimensions. Real OpenAI embeddings have 1536 dimensions. The number must be consistent across all rows in the column.

**Check the table structure:**

```sql
\d products
```

Expected output (yours will differ):
```
                             Table "public.products"
  Column   |   Type    | Collation | Nullable |           Default
-----------+-----------+-----------+----------+------------------------------
 id        | integer   |           | not null | nextval('products_id_seq'...)
 name      | text      |           | not null |
 category  | text      |           |          |
 embedding | vector(4) |           |          |
```

---

## Part 3 - Insert Sample Embeddings

Insert several products with manually crafted embeddings. In this example, "electronics" items will have embeddings clustered together, and "furniture" items will be in a different cluster.

```sql
INSERT INTO products (name, category, embedding) VALUES
  ('Laptop Pro 15',      'electronics', '[0.85, 0.92, 0.11, 0.03]'),
  ('Wireless Keyboard',  'electronics', '[0.82, 0.89, 0.14, 0.07]'),
  ('USB-C Hub',          'electronics', '[0.79, 0.88, 0.09, 0.12]'),
  ('Gaming Mouse',       'electronics', '[0.80, 0.91, 0.10, 0.05]'),
  ('Oak Desk',           'furniture',   '[0.05, 0.08, 0.87, 0.91]'),
  ('Ergonomic Chair',    'furniture',   '[0.07, 0.10, 0.83, 0.88]'),
  ('Bookshelf 5-Shelf',  'furniture',   '[0.04, 0.06, 0.90, 0.85]'),
  ('Standing Desk Mat',  'furniture',   '[0.09, 0.12, 0.81, 0.84]');
```

**Verify the inserts:**

```sql
SELECT id, name, category, embedding
FROM products
ORDER BY id;
```

Expected output (yours will differ):
```
 id |       name        |  category   |       embedding
----+-------------------+-------------+-----------------------
  1 | Laptop Pro 15     | electronics | [0.85,0.92,0.11,0.03]
  2 | Wireless Keyboard | electronics | [0.82,0.89,0.14,0.07]
  ...
(8 rows)
```

---

## Part 4 - Run Similarity Searches

### L2 Distance (Euclidean)

L2 distance measures the straight-line distance between two points in vector space. Smaller distance = more similar.

```sql
-- Find the 3 products most similar to a "laptop-like" query vector
SELECT
  name,
  category,
  embedding <-> '[0.84, 0.90, 0.12, 0.05]' AS l2_distance
FROM products
ORDER BY l2_distance ASC
LIMIT 3;
```

The `<->` operator computes L2 distance. `ORDER BY ASC` returns the closest (most similar) first.

Expected output (yours will differ):
```
       name        |  category   |     l2_distance
-------------------+-------------+---------------------
 Laptop Pro 15     | electronics | 0.02236...
 Gaming Mouse      | electronics | 0.05000...
 Wireless Keyboard | electronics | 0.06083...
(3 rows)
```

The electronics items correctly rank as most similar to the laptop-like query.

### Cosine Distance

Cosine distance measures the angle between two vectors, not their magnitude. It is the standard metric for text embeddings from models like OpenAI.

```sql
SELECT
  name,
  category,
  embedding <=> '[0.84, 0.90, 0.12, 0.05]' AS cosine_distance
FROM products
ORDER BY cosine_distance ASC
LIMIT 3;
```

The `<=>` operator computes cosine distance. A value of 0 means identical direction; 2 means completely opposite.

Expected output (yours will differ):
```
       name        |  category   |   cosine_distance
-------------------+-------------+--------------------
 Gaming Mouse      | electronics | 0.000006...
 Laptop Pro 15     | electronics | 0.000015...
 Wireless Keyboard | electronics | 0.000042...
(3 rows)
```

### Negative Inner Product (Dot Product)

```sql
SELECT
  name,
  category,
  embedding <#> '[0.84, 0.90, 0.12, 0.05]' AS neg_inner_product
FROM products
ORDER BY neg_inner_product ASC
LIMIT 3;
```

The `<#>` operator computes the negative inner product. If your embeddings are normalized (unit length), this is equivalent to cosine similarity. Some model providers recommend this metric.

---

## Part 5 - Create Indexes

Without an index, every similarity search scans all rows (sequential scan). For tables with millions of rows, this is too slow. pgvector offers two index types.

### IVFFlat Index

IVFFlat clusters vectors into groups (called lists) at index build time. At query time, it only searches the most relevant clusters.

```sql
-- Build IVFFlat index on L2 distance
CREATE INDEX ON products
USING ivfflat (embedding vector_l2_ops)
WITH (lists = 2);
```

The `lists` parameter controls how many clusters to create. A common starting point is `sqrt(row_count)`. For production with millions of rows, you might use 100-1000 lists. With only 8 rows here, 2 lists is reasonable.

The `vector_l2_ops` operator class tells the index to optimize for L2 distance searches. Use `vector_cosine_ops` for cosine distance.

**Check the index was created:**

```sql
\d products
```

Expected output (yours will differ):
```
Indexes:
    "products_pkey" PRIMARY KEY, btree (id)
    "products_embedding_idx" ivfflat (embedding vector_l2_ops) WITH (lists=2)
```

**Set the probes parameter for query accuracy:**

```sql
SET ivfflat.probes = 2;
```

`probes` controls how many clusters to search at query time. Higher probes = higher accuracy = slower query. Default is 1. For high-recall applications, use `probes = sqrt(lists)`.

**Run the L2 search again - it will now use the index:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT name, embedding <-> '[0.84, 0.90, 0.12, 0.05]' AS dist
FROM products
ORDER BY dist ASC
LIMIT 3;
```

Look for `Index Scan using products_embedding_idx` in the output.

### HNSW Index

HNSW (Hierarchical Navigable Small World) builds a multi-layer graph structure. It is faster at query time than IVFFlat but takes longer to build and uses more memory.

**Drop the IVFFlat index first:**

```sql
DROP INDEX products_embedding_idx;
```

**Create HNSW index:**

```sql
CREATE INDEX ON products
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);
```

`m` is the number of connections per node in the graph (default 16). Higher m = better recall, more memory. `ef_construction` is the size of the candidate list during index build (default 64). Higher ef_construction = better index quality, longer build time.

**Set the query-time search parameter:**

```sql
SET hnsw.ef_search = 40;
```

`ef_search` controls how many candidates to consider during query (default 40). Higher = more accurate but slower.

**Run a cosine search:**

```sql
SELECT name, embedding <=> '[0.84, 0.90, 0.12, 0.05]' AS cosine_dist
FROM products
ORDER BY cosine_dist ASC
LIMIT 3;
```

### Choosing Between IVFFlat and HNSW

| Factor | IVFFlat | HNSW |
|---|---|---|
| Build time | Fast | Slow (especially for large tables) |
| Query speed | Good | Excellent |
| Memory usage | Low | High |
| Recall (accuracy) | Good | Better |
| Best for | Tables with frequent inserts | Read-heavy workloads |
| Can build on non-empty table | Yes, but slower | Yes, but slower |

**Rule of thumb:** Start with IVFFlat. Move to HNSW if query latency is too high and you can afford the memory and build time.

---

## Part 6 - RDS vs Aurora for pgvector

Both RDS PostgreSQL and Aurora PostgreSQL support pgvector, but there are differences.

| Feature | RDS PostgreSQL | Aurora PostgreSQL |
|---|---|---|
| pgvector available | Yes | Yes |
| Supported versions | Same as extension policy | Same as extension policy |
| Read replicas | Manual setup | Native Aurora read replicas |
| Scaling reads | One replica at a time | Up to 15 replicas automatically |
| Storage | Standard EBS | Aurora distributed storage |
| Optimized reads (io2) | No | Yes (for large datasets) |
| Cost | Lower | Higher |

**When to use Aurora for pgvector:**
- Your vector dataset is large (tens of millions of vectors)
- You have many concurrent similarity search requests
- You want read replicas without manual replication setup
- You want Aurora Optimized Reads to cache frequently-accessed index pages

**When RDS is fine for pgvector:**
- Smaller datasets (under a few million vectors)
- Low to moderate query concurrency
- Cost is a primary concern

---

## Part 7 - RAG Patterns with Aurora and Amazon Bedrock

RAG (Retrieval Augmented Generation) is the most common production use case for pgvector. Instead of fine-tuning an LLM on your data, you store your documents as embeddings in PostgreSQL and retrieve the most relevant ones at query time.

### How RAG Works with Aurora

```
User asks: "What is the refund policy?"

1. Your app sends the question to an embedding model (e.g. Amazon Titan, OpenAI)
2. The model returns a vector: [0.12, 0.85, 0.34, ...]
3. Your app queries Aurora: SELECT content FROM docs ORDER BY embedding <=> $1 LIMIT 5
4. Aurora returns the 5 most relevant document chunks
5. Your app sends those chunks + the question to an LLM
6. The LLM generates an answer grounded in your actual documents
```

### Set Up a RAG-Ready Table

```sql
CREATE TABLE knowledge_base (
    id SERIAL PRIMARY KEY,
    source_file TEXT NOT NULL,
    chunk_index INT NOT NULL,
    content TEXT NOT NULL,
    embedding vector(1536),  -- 1536 dimensions for Amazon Titan / OpenAI ada-002
    metadata JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- HNSW index for fast similarity search
CREATE INDEX ON knowledge_base
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Filter index for metadata queries
CREATE INDEX ON knowledge_base USING gin (metadata);
```

The `vector(1536)` dimension matches the output of Amazon Titan Text Embeddings v2 and OpenAI text-embedding-ada-002. If you use a different model, adjust the dimension count.

### Insert Sample Chunks (Simulated Embeddings)

In production, you would generate embeddings using the Bedrock API or OpenAI API. For this lab, use random vectors to practice the query pattern:

```sql
INSERT INTO knowledge_base (source_file, chunk_index, content, embedding)
SELECT
    'policy-doc-' || (i / 10 + 1) || '.pdf',
    i % 10,
    'This is chunk ' || i || ' of the document. It contains information about topic ' || (i % 5),
    ('[' || array_to_string(ARRAY(SELECT (random())::FLOAT8 FROM generate_series(1, 1536)), ',') || ']')::vector
FROM generate_series(1, 100) AS s(i);
```

### The RAG Query Pattern

This is the query your application runs on every user question:

```sql
-- $1 is the embedding of the user's question (generated by the embedding model)
SELECT
    source_file,
    chunk_index,
    content,
    1 - (embedding <=> $1) AS similarity_score
FROM knowledge_base
ORDER BY embedding <=> $1
LIMIT 5;
```

The `1 - cosine_distance` gives a similarity score from 0 (unrelated) to 1 (identical).

### Filter by Metadata

Add metadata filters to narrow the search scope:

```sql
SELECT content, 1 - (embedding <=> $1) AS score
FROM knowledge_base
WHERE metadata @> '{"department": "engineering"}'
ORDER BY embedding <=> $1
LIMIT 5;
```

The `@>` operator checks if the metadata JSONB contains the specified key-value pair. Combined with the GIN index on metadata, this is efficient.

### Amazon Bedrock Knowledge Base Integration

If you want AWS to manage the entire RAG pipeline, you can use Amazon Bedrock Knowledge Bases with Aurora PostgreSQL as the vector store. This automates:
- Document ingestion (PDF, HTML, text)
- Chunking (splitting documents into searchable pieces)
- Embedding generation (using Amazon Titan)
- Storage in Aurora pgvector
- Retrieval at query time

**Setup overview (Console):**
1. Go to Amazon Bedrock > Knowledge bases
2. Click **Create knowledge base**
3. For the data source, choose S3 (where your documents are stored)
4. For the vector database, choose **Amazon Aurora**
5. Provide your Aurora cluster endpoint, database name, and credentials
6. Bedrock creates the required table and indexes automatically
7. Click **Sync** to ingest your documents

> **Note:** Bedrock Knowledge Bases require Aurora PostgreSQL (not RDS PostgreSQL). The cluster must be accessible from the Bedrock service (VPC configuration required). See the AWS docs for VPC endpoint setup.

### Performance Tips for RAG at Scale

1. **Dimension matters:** 1536 dimensions is standard but larger models output 3072+ dimensions. Higher dimensions = more storage and slower searches. Consider dimensionality reduction if latency is critical.
2. **Chunk size:** 500-1000 tokens per chunk is a good starting point. Too small = missing context. Too large = diluted relevance.
3. **Index type:** Use HNSW for production RAG workloads. The query latency improvement over IVFFlat is significant at millions of rows.
4. **ef_search tuning:** Start with 40 (default). Increase to 100-200 if recall is more important than latency.
5. **Partitioning:** For very large knowledge bases (100M+ vectors), consider partitioning by source or department and using partition pruning with metadata filters.

---

## Cleanup

```sql
DROP TABLE IF EXISTS knowledge_base;
DROP TABLE IF EXISTS products;
-- Keep the extension for USE exercise 03
```

---

## Summary

| Task | Command |
|---|---|
| Install pgvector | `CREATE EXTENSION vector;` |
| Create vector column | `vector(N)` in CREATE TABLE |
| L2 search | `<->` operator, `vector_l2_ops` |
| Cosine search | `<=>` operator, `vector_cosine_ops` |
| IVFFlat index | `USING ivfflat ... WITH (lists=N)` |
| HNSW index | `USING hnsw ... WITH (m=16, ef_construction=64)` |

---

## Next Steps

- [BUILD 05 - Trusted Language Extensions](05-trusted-language-extensions.md)
- [USE 03 - Vector Search](../use/03-vector-search.md)
