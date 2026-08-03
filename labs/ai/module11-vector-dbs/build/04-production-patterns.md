# Build 04: Production Patterns

Running pgvector in production requires the same care as any PostgreSQL deployment - plus a few vector-specific considerations. This guide covers batch operations, monitoring, maintenance, and common pitfalls.

---

## Step 1. Batch embedding insertion

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import numpy as np
import time

conn = psycopg2.connect(host="localhost", port=5432, user=os.environ.get("USER"), dbname="postgres")
cur = conn.cursor()

print("""
In production, you often need to insert thousands of vectors at once.
Single INSERT statements are slow. Use batch operations instead.
""")

# Create a test table
cur.execute("DROP TABLE IF EXISTS batch_test")
cur.execute("CREATE TABLE batch_test (id SERIAL PRIMARY KEY, embedding vector(384))")
conn.commit()

np.random.seed(42)
n_vectors = 5000
dim = 384

# Method 1: Single inserts (slow)
print("Method 1: Single INSERTs")
vectors = np.random.randn(1000, dim).astype(np.float32)
start = time.time()
for v in vectors:
    cur.execute("INSERT INTO batch_test (embedding) VALUES (%s)", (str(v.tolist()),))
conn.commit()
method1_time = time.time() - start
print(f"  1,000 inserts: {method1_time:.2f}s ({method1_time/1000*1000:.1f}ms per insert)")

# Clear table
cur.execute("TRUNCATE batch_test")
conn.commit()

# Method 2: executemany (better)
print("\nMethod 2: executemany")
start = time.time()
values = [(str(v.tolist()),) for v in vectors]
cur.executemany("INSERT INTO batch_test (embedding) VALUES (%s)", values)
conn.commit()
method2_time = time.time() - start
print(f"  1,000 inserts: {method2_time:.2f}s ({method2_time/1000*1000:.1f}ms per insert)")

# Clear table
cur.execute("TRUNCATE batch_test")
conn.commit()

# Method 3: COPY (fastest)
print("\nMethod 3: COPY (fastest for bulk loading)")
from io import StringIO

start = time.time()
# Build a tab-separated string of all vectors
buffer = StringIO()
for i, v in enumerate(vectors):
    vec_str = "[" + ",".join(f"{x:.6f}" for x in v) + "]"
    buffer.write(f"{vec_str}\n")
    # pgvector COPY format: [0.1,0.2,0.3,...] (one per line)
buffer.seek(0)  # rewind to start
# .seek(0) moves the read position back to the beginning

cur.copy_expert("COPY batch_test (embedding) FROM STDIN", buffer)
# COPY is PostgreSQL's fastest bulk insert method
conn.commit()
method3_time = time.time() - start
print(f"  1,000 inserts: {method3_time:.2f}s ({method3_time/1000*1000:.1f}ms per insert)")

print(f"\nSpeedup: COPY is {method1_time/method3_time:.0f}x faster than single INSERTs")

cur.close()
conn.close()
PYEOF
```

Expected output (yours will differ):

```
Method 1: Single INSERTs
  1,000 inserts: 2.45s (2.5ms per insert)

Method 2: executemany
  1,000 inserts: 1.12s (1.1ms per insert)

Method 3: COPY (fastest for bulk loading)
  1,000 inserts: 0.18s (0.2ms per insert)

Speedup: COPY is 14x faster than single INSERTs
```

---

## Step 2. Monitor vector table health

On your **Mac terminal**, run:

```bash
psql -h localhost -p 5432 -U $(whoami) -d postgres << 'SQL'
-- Vector-specific monitoring queries

-- 1. Table and index sizes
SELECT
    pg_size_pretty(pg_relation_size('vector_bench')) AS table_size,
    pg_size_pretty(pg_indexes_size('vector_bench')) AS index_size,
    pg_size_pretty(pg_total_relation_size('vector_bench')) AS total_size;

-- 2. Row count and vector dimensions
SELECT
    count(*) AS row_count,
    avg(vector_dims(embedding)) AS avg_dims
    -- vector_dims() returns the number of dimensions
FROM vector_bench;

-- 3. Check if indexes exist and their types
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'vector_bench';

-- 4. Check for bloat (dead tuples)
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    CASE WHEN n_live_tup > 0
        THEN round(100.0 * n_dead_tup / n_live_tup, 1)
        ELSE 0
    END AS dead_pct
FROM pg_stat_user_tables
WHERE relname IN ('vector_bench', 'documents');
SQL
```

---

## Step 3. Index maintenance

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Vector Index Maintenance Guide:

IVFFlat:
  - After bulk inserts (> 10% of table size): REINDEX
  - Cluster centers don't update automatically
  - Without REINDEX, new vectors may not be in the right cluster
  - Schedule: REINDEX after each batch import

  REINDEX INDEX CONCURRENTLY idx_ivfflat;
  -- CONCURRENTLY avoids locking (production-safe)

HNSW:
  - Supports incremental inserts (no REINDEX needed)
  - But quality degrades slowly with many updates/deletes
  - Schedule: REINDEX monthly or after major data changes

  REINDEX INDEX CONCURRENTLY idx_hnsw;

Both:
  - Run VACUUM ANALYZE after major changes
  - Monitor index size vs table size (index shouldn't be > 3x table)
  - Monitor recall: periodically run exact search and compare

Memory considerations:
  - Vector dimensions directly affect memory usage
  - 1M vectors x 384 dims x 4 bytes = 1.5 GB just for data
  - HNSW index adds 2-3x more memory
  - Set maintenance_work_mem high for index builds:
    SET maintenance_work_mem = '2GB';

Performance tuning:
  - effective_cache_size: set to 75% of available RAM
  - shared_buffers: 25% of RAM (standard PostgreSQL)
  - work_mem: 256MB+ for vector queries with sorting
  - maintenance_work_mem: 2GB+ for index builds
""")
PYEOF
```

---

## Step 4. Embedding refresh strategy

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Embedding Refresh Strategy:

Problem: Your documents change, but embeddings don't update automatically.
A document that says "PostgreSQL 14" might be updated to "PostgreSQL 17"
but the embedding still reflects the old content.

Strategy 1: Update on write
  - Re-generate embedding whenever content changes
  - Simplest but adds latency to writes
  - Good for: small documents, infrequent updates

  CREATE OR REPLACE FUNCTION update_embedding()
  RETURNS trigger AS $$
  BEGIN
      -- Call your embedding API here
      -- NEW.embedding = generate_embedding(NEW.content);
      RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  CREATE TRIGGER trg_update_embedding
  BEFORE UPDATE OF content ON documents
  FOR EACH ROW EXECUTE FUNCTION update_embedding();

Strategy 2: Background refresh
  - Mark documents as "stale" when content changes
  - Background job re-generates embeddings periodically
  - Good for: large documents, frequent updates, batch processing

  ALTER TABLE documents ADD COLUMN embedding_stale BOOLEAN DEFAULT FALSE;

  -- On content update, mark as stale
  CREATE TRIGGER trg_mark_stale
  BEFORE UPDATE OF content ON documents
  FOR EACH ROW EXECUTE FUNCTION mark_embedding_stale();

  -- Background job refreshes stale embeddings
  -- SELECT id, content FROM documents WHERE embedding_stale = TRUE LIMIT 100;
  -- For each: generate new embedding, UPDATE ... SET embedding = ..., embedding_stale = FALSE

Strategy 3: Version-based refresh
  - Track embedding model version
  - When you upgrade your embedding model, regenerate all embeddings
  - Good for: model upgrades, ensuring consistency

  ALTER TABLE documents ADD COLUMN embedding_model TEXT DEFAULT 'all-MiniLM-L6-v2';
  ALTER TABLE documents ADD COLUMN embedding_updated_at TIMESTAMP DEFAULT NOW();

  -- Find embeddings from old model
  SELECT count(*) FROM documents WHERE embedding_model != 'all-MiniLM-L6-v2-v2';

Best Practice:
  1. Always store: embedding_model, embedding_updated_at
  2. Use background refresh for production (don't block writes)
  3. After model upgrade: regenerate ALL embeddings (don't mix models!)
  4. Monitor: alert when > 5% of embeddings are stale
""")
PYEOF
```

---

## What You Learned

| Pattern | What It Does | When to Use |
|---------|-------------|-------------|
| Batch COPY | Fastest bulk vector insert | Initial data loading, batch imports |
| Table monitoring | Track sizes, bloat, index health | Daily production monitoring |
| REINDEX CONCURRENTLY | Rebuild vector index without locks | After major data changes |
| Embedding refresh | Keep vectors in sync with content | When source documents change |
| Memory tuning | Optimize for vector workloads | Production deployment |
