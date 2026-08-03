# Build 02: Vector Indexes - IVFFlat vs HNSW

Without an index, vector search does a sequential scan - comparing your query against every single vector. This works for 1,000 rows but not for 1,000,000. This guide covers the two index types pgvector supports and how to tune them.

---

## Step 1. See why indexes matter

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import numpy as np
import time

conn = psycopg2.connect(host="localhost", port=5432, user=os.environ.get("USER"), dbname="postgres")
cur = conn.cursor()

# Create a test table with many vectors
cur.execute("DROP TABLE IF EXISTS vector_bench")
cur.execute("CREATE TABLE vector_bench (id SERIAL PRIMARY KEY, embedding vector(128))")
# Using 128 dims for speed (real models use 384-1536)

# Insert 50,000 random vectors
np.random.seed(42)
batch_size = 1000
total = 50000

print(f"Inserting {total:,} vectors (128 dimensions each)...")
start = time.time()

for batch_start in range(0, total, batch_size):
    vectors = np.random.randn(batch_size, 128).astype(np.float32)
    values = [(str(v.tolist()),) for v in vectors]
    # Create list of tuples for executemany
    cur.executemany("INSERT INTO vector_bench (embedding) VALUES (%s)", values)
    # executemany runs the same query for each tuple in the list

conn.commit()
insert_time = time.time() - start
print(f"Inserted in {insert_time:.1f}s")
print()

# Search WITHOUT index (sequential scan)
query = np.random.randn(128).tolist()
query_str = str(query)

cur.execute("SET enable_indexscan = off")  # force sequential scan

start = time.time()
cur.execute("""
    SELECT id, embedding <=> %s::vector AS distance
    FROM vector_bench
    ORDER BY embedding <=> %s::vector
    LIMIT 10
""", (query_str, query_str))
results_seq = cur.fetchall()
seq_time = time.time() - start

cur.execute("SET enable_indexscan = on")  # re-enable

print(f"Sequential scan (no index): {seq_time*1000:.1f} ms")
print(f"  Top result: id={results_seq[0][0]}, distance={results_seq[0][1]:.4f}")

cur.close()
conn.close()

print()
print(f"At {total:,} vectors, sequential scan takes {seq_time*1000:.0f}ms")
print(f"At 1,000,000 vectors, it would take ~{seq_time*1000*20:.0f}ms")
print(f"At 10,000,000 vectors, it would take ~{seq_time*1000*200:.0f}ms")
print("You NEED an index for production vector search.")
PYEOF
```

---

## Step 2. IVFFlat index

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
IVFFlat: Inverted File with Flat storage

How it works:
  1. Divides all vectors into 'nlist' clusters (like table partitions)
  2. Each vector belongs to its nearest cluster center
  3. At query time, searches only 'nprobe' nearest clusters
  4. More clusters searched (nprobe) = better recall but slower

DBA analogy: Like range partitioning
  - nlist = number of partitions
  - nprobe = how many partitions to search
  - Partition pruning = only scan relevant clusters
""")

# Create IVFFlat index
nlist = 100  # number of clusters (rule of thumb: sqrt(total_rows))
# For 50,000 rows, sqrt(50000) = 224, but 100 is a common starting point

print(f"Creating IVFFlat index with {nlist} clusters...")
start = time.time()

cur.execute(f"""
    CREATE INDEX IF NOT EXISTS idx_ivfflat
    ON vector_bench
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = {nlist})
""")
# USING ivfflat: use the IVFFlat algorithm
# vector_cosine_ops: use cosine distance (match <=> operator)
# lists = 100: create 100 clusters

conn.commit()
build_time = time.time() - start
print(f"Index built in {build_time:.1f}s")
print()

# Search with different nprobe values
query = np.random.randn(128).tolist()
query_str = str(query)

# Get exact results first (no index) for recall comparison
cur.execute("SET enable_indexscan = off")
cur.execute("""
    SELECT id FROM vector_bench
    ORDER BY embedding <=> %s::vector LIMIT 10
""", (query_str,))
# set() creates a collection with no duplicates (like SELECT DISTINCT).
# .intersection() finds items in BOTH sets (like INTERSECT in SQL).
# set_a - set_b finds items in A but not in B (like EXCEPT in SQL).
exact_ids = set(row[0] for row in cur.fetchall())
cur.execute("SET enable_indexscan = on")

print(f"{'nprobe':>7s}  {'Time (ms)':>10s}  {'Recall@10':>10s}")
print("-" * 32)

for nprobe in [1, 5, 10, 20, 50, 100]:
    cur.execute(f"SET ivfflat.probes = {nprobe}")
    # ivfflat.probes controls how many clusters to search at query time

    start = time.time()
    cur.execute("""
        SELECT id FROM vector_bench
        ORDER BY embedding <=> %s::vector LIMIT 10
    """, (query_str,))
    results = cur.fetchall()
    query_time = (time.time() - start) * 1000

    result_ids = set(row[0] for row in results)
    recall = len(result_ids.intersection(exact_ids)) / len(exact_ids)
    # recall = how many of the true top-10 did we find?

    print(f"{nprobe:>7d}  {query_time:>9.1f}  {recall:>9.0%}")

print()
print("More probes = higher recall but slower")
print("Sweet spot: nprobe = 10-20 for most workloads")
print("Rule of thumb: nprobe = sqrt(nlist)")

cur.close()
conn.close()
PYEOF
```

Expected output (yours will differ):

```
IVFFlat index with 100 clusters...
Index built in 2.3s

 nprobe   Time (ms)  Recall@10
--------------------------------
      1        0.5        30%
      5        1.2        70%
     10        2.1        90%
     20        3.8       100%
     50        8.2       100%
    100       15.4       100%
```

---

## Step 3. HNSW index

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
HNSW: Hierarchical Navigable Small World

How it works:
  1. Builds a multi-layer graph connecting similar vectors
  2. Top layers have few nodes (coarse navigation)
  3. Bottom layers have all nodes (fine-grained search)
  4. Query navigates from top to bottom, finding neighbors

DBA analogy: Like a B-tree, but for vectors
  - Root level: few nodes, big jumps
  - Leaf level: all nodes, small jumps
  - Navigate from root to leaf to find nearest neighbors

Key parameters:
  m = connections per node (like B-tree fanout)
  ef_construction = search depth when building (higher = better index, slower build)
  ef_search = search depth at query time (higher = better recall, slower query)
""")

# Drop old index
cur.execute("DROP INDEX IF EXISTS idx_ivfflat")

# Create HNSW index
m = 16              # connections per node (default: 16, range: 2-100)
ef_construction = 64  # construction search depth (default: 64, range: 4-1000)

print(f"Creating HNSW index (m={m}, ef_construction={ef_construction})...")
start = time.time()

cur.execute(f"""
    CREATE INDEX idx_hnsw
    ON vector_bench
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = {m}, ef_construction = {ef_construction})
""")
# m = 16: each node connects to 16 neighbors
# ef_construction = 64: search depth during index build

conn.commit()
build_time = time.time() - start
print(f"Index built in {build_time:.1f}s")
print()

# Get exact results
query = np.random.randn(128).tolist()
query_str = str(query)

cur.execute("SET enable_indexscan = off")
cur.execute("SELECT id FROM vector_bench ORDER BY embedding <=> %s::vector LIMIT 10", (query_str,))
exact_ids = set(row[0] for row in cur.fetchall())
cur.execute("SET enable_indexscan = on")

# Test with different ef_search values
print(f"{'ef_search':>10s}  {'Time (ms)':>10s}  {'Recall@10':>10s}")
print("-" * 35)

for ef_search in [10, 20, 40, 80, 200, 400]:
    cur.execute(f"SET hnsw.ef_search = {ef_search}")
    # hnsw.ef_search controls search depth at query time

    start = time.time()
    cur.execute("SELECT id FROM vector_bench ORDER BY embedding <=> %s::vector LIMIT 10", (query_str,))
    results = cur.fetchall()
    query_time = (time.time() - start) * 1000

    result_ids = set(row[0] for row in results)
    recall = len(result_ids.intersection(exact_ids)) / len(exact_ids)

    print(f"{ef_search:>10d}  {query_time:>9.1f}  {recall:>9.0%}")

print()
print("HNSW typically achieves higher recall than IVFFlat at similar speed")
print("Default ef_search = 40 is good for most workloads")

cur.close()
conn.close()
PYEOF
```

Expected output (yours will differ):

```
HNSW index (m=16, ef_construction=64)...
Index built in 8.5s

 ef_search   Time (ms)  Recall@10
-----------------------------------
        10        0.3        70%
        20        0.5        90%
        40        0.8       100%
        80        1.5       100%
       200        3.2       100%
       400        6.1       100%
```

---

## Step 4. IVFFlat vs HNSW comparison

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
IVFFlat vs HNSW - When to Use Each:

| Factor          | IVFFlat              | HNSW                |
|-----------------|----------------------|---------------------|
| Build speed     | Fast (seconds)       | Slow (minutes)      |
| Query speed     | Good                 | Excellent           |
| Memory usage    | Low                  | High (2-3x more)    |
| Recall@10       | 90-95%               | 97-99%              |
| Insert support  | Need REINDEX after   | Supports incremental|
| Best for        | Large data, low mem  | Performance-critical|

Decision guide:
  1. < 100K vectors: HNSW (memory is not an issue)
  2. 100K - 1M vectors: HNSW if memory allows, IVFFlat if not
  3. > 1M vectors: IVFFlat or consider dedicated vector DB
  4. Frequent inserts: HNSW (handles inserts without reindex)
  5. Rarely updated: IVFFlat (build once, query many)

Tuning cheat sheet:

IVFFlat:
  lists = sqrt(total_rows)        -- number of clusters
  probes = sqrt(lists)            -- clusters to search
  More probes = better recall, slower queries

HNSW:
  m = 16                          -- connections per node (default is good)
  ef_construction = 64-256        -- higher = better index, slower build
  ef_search = 40-200              -- higher = better recall, slower queries

Both:
  maintenance_work_mem = 2GB+     -- for faster index builds
  shared_buffers = adequate       -- vectors are large, need buffer space
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | When to Use |
|---------|-------------|-------------|
| Sequential scan | Compare query to every vector | Testing only, never in production |
| IVFFlat index | Cluster-based approximate search | Large datasets, limited memory |
| HNSW index | Graph-based approximate search | Performance-critical, high recall needed |
| nprobe (IVFFlat) | How many clusters to search | Higher = better recall, slower |
| ef_search (HNSW) | Search depth at query time | Higher = better recall, slower |
| Recall@K | % of true top-K results found | Quality metric for ANN indexes |
