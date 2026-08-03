# SURVIVE 01: The Recall Disaster

Your RAG system answers questions about PostgreSQL documentation. Users report that it can't find relevant documents even though they exist in the database. The vector index has low recall - it's missing 40% of the best matches.

---

## The Scenario

A DBA set up pgvector with an IVFFlat index using default settings on 500,000 vectors. Queries return in 5ms (fast!) but the results are mediocre. The index was built with too few clusters and the search uses too few probes, so the best matches are in clusters that never get searched.

---

## Step 1. See the problem

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import numpy as np
import time

conn = psycopg2.connect(host="localhost", port=5432, user=os.environ.get("USER"), dbname="postgres")
cur = conn.cursor()

np.random.seed(42)

# Setup: create table with vectors
cur.execute("DROP TABLE IF EXISTS recall_test")
cur.execute("CREATE TABLE recall_test (id SERIAL PRIMARY KEY, embedding vector(128))")

# Insert 50,000 vectors
print("Inserting 50,000 vectors...")
from io import StringIO
buffer = StringIO()
vectors = np.random.randn(50000, 128).astype(np.float32)
for v in vectors:
    buffer.write("[" + ",".join(f"{x:.6f}" for x in v) + "]\n")
buffer.seek(0)
cur.copy_expert("COPY recall_test (embedding) FROM STDIN", buffer)
conn.commit()

# BAD INDEX: too few clusters, default probes
print("\nCreating BAD IVFFlat index (10 clusters, 1 probe)...")
cur.execute("""
    CREATE INDEX idx_bad ON recall_test
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 10)
""")
# lists = 10 is far too few for 50,000 vectors
# Rule of thumb: lists = sqrt(n) = sqrt(50000) = ~224
conn.commit()

cur.execute("SET ivfflat.probes = 1")
# probes = 1 means only search 1 out of 10 clusters

# Get exact results
query = np.random.randn(128).tolist()
query_str = str(query)

cur.execute("SET enable_indexscan = off")
cur.execute("SELECT id FROM recall_test ORDER BY embedding <=> %s::vector LIMIT 10", (query_str,))
exact_top10 = set(row[0] for row in cur.fetchall())
cur.execute("SET enable_indexscan = on")

# Search with bad index
start = time.time()
cur.execute("SELECT id FROM recall_test ORDER BY embedding <=> %s::vector LIMIT 10", (query_str,))
bad_results = set(row[0] for row in cur.fetchall())
bad_time = (time.time() - start) * 1000

bad_recall = len(bad_results.intersection(exact_top10)) / len(exact_top10)

print(f"\nBAD Index Results:")
print(f"  Lists: 10 (should be ~224)")
print(f"  Probes: 1 (should be ~15)")
print(f"  Query time: {bad_time:.1f}ms")
print(f"  Recall@10: {bad_recall:.0%}")
print(f"  Missed: {10 - int(bad_recall * 10)}/10 of the best results!")

if bad_recall < 0.7:
    print(f"\n  CRITICAL: recall below 70%!")
    print(f"  The RAG system is missing the best documents.")
    print(f"  Users see irrelevant results even though better ones exist.")

# Clean up
cur.execute("DROP INDEX idx_bad")
conn.commit()

cur.close()
conn.close()
PYEOF
```

---

## Step 2. Fix it

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import numpy as np
import time

conn = psycopg2.connect(host="localhost", port=5432, user=os.environ.get("USER"), dbname="postgres")
cur = conn.cursor()

np.random.seed(42)
query = np.random.randn(128).tolist()
query_str = str(query)

# Get exact results
cur.execute("SET enable_indexscan = off")
cur.execute("SELECT id FROM recall_test ORDER BY embedding <=> %s::vector LIMIT 10", (query_str,))
exact_top10 = set(row[0] for row in cur.fetchall())
cur.execute("SET enable_indexscan = on")

# Fix 1: Better IVFFlat (proper lists and probes)
n_rows = 50000
good_lists = int(np.sqrt(n_rows))  # sqrt(50000) = 224

print(f"Fix 1: IVFFlat with lists={good_lists}, probes=15")
cur.execute(f"""
    CREATE INDEX idx_good_ivf ON recall_test
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = {good_lists})
""")
conn.commit()

cur.execute("SET ivfflat.probes = 15")
start = time.time()
cur.execute("SELECT id FROM recall_test ORDER BY embedding <=> %s::vector LIMIT 10", (query_str,))
good_ivf_results = set(row[0] for row in cur.fetchall())
good_ivf_time = (time.time() - start) * 1000
good_ivf_recall = len(good_ivf_results.intersection(exact_top10)) / len(exact_top10)

print(f"  Query time: {good_ivf_time:.1f}ms")
print(f"  Recall@10: {good_ivf_recall:.0%}")
cur.execute("DROP INDEX idx_good_ivf")
conn.commit()

# Fix 2: HNSW (usually better recall)
print(f"\nFix 2: HNSW (m=16, ef_construction=128, ef_search=80)")
cur.execute("""
    CREATE INDEX idx_hnsw ON recall_test
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 128)
""")
conn.commit()

cur.execute("SET hnsw.ef_search = 80")
start = time.time()
cur.execute("SELECT id FROM recall_test ORDER BY embedding <=> %s::vector LIMIT 10", (query_str,))
hnsw_results = set(row[0] for row in cur.fetchall())
hnsw_time = (time.time() - start) * 1000
hnsw_recall = len(hnsw_results.intersection(exact_top10)) / len(exact_top10)

print(f"  Query time: {hnsw_time:.1f}ms")
print(f"  Recall@10: {hnsw_recall:.0%}")

print(f"\nComparison:")
print(f"  {'Method':25s}  {'Time':>8s}  {'Recall':>8s}")
print(f"  {'-'*45}")
print(f"  {'Bad IVFFlat (10/1)':25s}  {'slow':>8s}  {'<70%':>8s}")
print(f"  {'Good IVFFlat (224/15)':25s}  {good_ivf_time:>7.1f}ms  {good_ivf_recall:>7.0%}")
print(f"  {'HNSW (m=16, ef=80)':25s}  {hnsw_time:>7.1f}ms  {hnsw_recall:>7.0%}")

cur.close()
conn.close()
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| IVFFlat lists too low | Low recall, misses best results | lists = sqrt(n_rows) |
| IVFFlat probes too low | Searches too few clusters | probes = sqrt(lists) |
| Never measuring recall | Don't know quality is bad | Periodic exact vs approximate comparison |
| Using IVFFlat defaults | 10 lists is rarely enough | Always calculate based on data size |
