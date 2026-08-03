# Build 03: Hybrid Search

Real-world vector search rarely uses similarity alone. You combine vector search (semantic meaning) with SQL filters (exact matches, ranges, categories). This is hybrid search - and it's what makes pgvector powerful.

---

## Step 1. Filter then search

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import numpy as np

try:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('all-MiniLM-L6-v2')
    USE_REAL = True
except ImportError:
    USE_REAL = False

conn = psycopg2.connect(host="localhost", port=5432, user=os.environ.get("USER"), dbname="postgres")
cur = conn.cursor()

def get_embedding(text):
    if USE_REAL:
        return model.encode([text])[0].tolist()
    np.random.seed(hash(text) % 2**32)
    return np.random.randn(384).tolist()

print("""
Hybrid Search: Combine vector similarity with SQL WHERE clauses.

Three patterns:
  1. Pre-filter: WHERE category = 'X' then ORDER BY similarity
  2. Post-filter: Get top-K similar, then filter in application
  3. Weighted: Combine similarity score with other relevance signals
""")

# Pattern 1: Pre-filter with SQL WHERE
query = "How do I fix slow queries?"
query_emb = str(get_embedding(query))

print(f"Query: '{query}'")
print()

# Search within performance category only
print("Pattern 1: Pre-filter (category = 'performance')")
print("-" * 55)
cur.execute("""
    SELECT title, category,
           1 - (embedding <=> %s::vector) AS similarity
    FROM documents
    WHERE category = 'performance'
    ORDER BY embedding <=> %s::vector
    LIMIT 3
""", (query_emb, query_emb))

for title, category, sim in cur.fetchall():
    print(f"  {sim:.3f}  [{category}]  {title}")

print()

# Search across all categories for comparison
print("Without filter (all categories):")
print("-" * 55)
cur.execute("""
    SELECT title, category,
           1 - (embedding <=> %s::vector) AS similarity
    FROM documents
    ORDER BY embedding <=> %s::vector
    LIMIT 3
""", (query_emb, query_emb))

for title, category, sim in cur.fetchall():
    print(f"  {sim:.3f}  [{category}]  {title}")

print()
print("Pre-filtering narrows results to one category")
print("Useful when the user specifies what they're looking for")

cur.close()
conn.close()
PYEOF
```

---

## Step 2. Weighted hybrid search (vector + keyword)

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import numpy as np

try:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('all-MiniLM-L6-v2')
    USE_REAL = True
except ImportError:
    USE_REAL = False

conn = psycopg2.connect(host="localhost", port=5432, user=os.environ.get("USER"), dbname="postgres")
cur = conn.cursor()

def get_embedding(text):
    if USE_REAL:
        return model.encode([text])[0].tolist()
    np.random.seed(hash(text) % 2**32)
    return np.random.randn(384).tolist()

# Add full-text search support
cur.execute("""
    ALTER TABLE documents
    ADD COLUMN IF NOT EXISTS search_vector tsvector
""")
cur.execute("""
    UPDATE documents
    SET search_vector = to_tsvector('english', title || ' ' || content)
""")
# to_tsvector creates a text search vector from title + content
# 'english' uses English stemming (running -> run, databases -> databas)

cur.execute("""
    CREATE INDEX IF NOT EXISTS idx_documents_fts
    ON documents USING gin(search_vector)
""")
# GIN index on the tsvector for fast full-text search
conn.commit()

print("""
Weighted Hybrid Search: Combine vector similarity with keyword matching.

Vector search:  Finds semantically similar content (meaning)
Keyword search: Finds exact term matches (precision)

Combined: score = (vector_weight * similarity) + (keyword_weight * keyword_score)
""")

query = "pg_stat_replication monitoring"
query_emb = str(get_embedding(query))

# Hybrid search: combine vector similarity with text search rank
cur.execute("""
    WITH vector_results AS (
        SELECT id, title, category, content,
               1 - (embedding <=> %s::vector) AS vector_score
        FROM documents
    ),
    keyword_results AS (
        SELECT id,
               ts_rank(search_vector, plainto_tsquery('english', %s)) AS keyword_score
        FROM documents
    )
    SELECT v.title, v.category,
           v.vector_score,
           COALESCE(k.keyword_score, 0) AS keyword_score,
           -- COALESCE returns 0 if keyword_score is NULL (no keyword match)
           0.7 * v.vector_score + 0.3 * COALESCE(k.keyword_score, 0) AS hybrid_score
           -- 70% vector (semantic meaning) + 30% keyword (exact match)
    FROM vector_results v
    LEFT JOIN keyword_results k ON v.id = k.id
    ORDER BY hybrid_score DESC
    LIMIT 5
""", (query_emb, query))
# plainto_tsquery converts search text to a tsquery for full-text search
# LEFT JOIN ensures we keep results even if there's no keyword match

print(f"Query: '{query}'")
print()
print(f"{'Title':40s}  {'Vector':>7s}  {'Keyword':>8s}  {'Hybrid':>7s}")
print("-" * 67)

for title, category, vscore, kscore, hscore in cur.fetchall():
    print(f"{title[:40]:40s}  {vscore:>7.3f}  {kscore:>8.3f}  {hscore:>7.3f}")

print()
print("Hybrid search boosts results that match BOTH meaning AND keywords")
print("'pg_stat_replication' keyword match + replication semantic match = highest score")

cur.close()
conn.close()
PYEOF
```

Expected output (yours will differ):

```
Query: 'pg_stat_replication monitoring'

Title                                     Vector  Keyword   Hybrid
-------------------------------------------------------------------
Replication Lag Monitoring                 0.654    0.312    0.551
PostgreSQL Replication Setup               0.621    0.089    0.461
pg_stat_statements Setup                   0.489    0.245    0.416
Logical Replication Setup                  0.578    0.067    0.425
```

---

## Step 3. Multi-filter search patterns

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import numpy as np

try:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('all-MiniLM-L6-v2')
    USE_REAL = True
except ImportError:
    USE_REAL = False

conn = psycopg2.connect(host="localhost", port=5432, user=os.environ.get("USER"), dbname="postgres")
cur = conn.cursor()

def get_embedding(text):
    if USE_REAL:
        return model.encode([text])[0].tolist()
    np.random.seed(hash(text) % 2**32)
    return np.random.randn(384).tolist()

print("Common Hybrid Search Patterns in Production")
print("=" * 60)

query = "database backup"
query_emb = str(get_embedding(query))

# Pattern A: Category filter + similarity
print("\nPattern A: Category + Similarity")
cur.execute("""
    SELECT title, 1 - (embedding <=> %s::vector) AS sim
    FROM documents
    WHERE category IN ('backup', 'replication')
    ORDER BY embedding <=> %s::vector
    LIMIT 3
""", (query_emb, query_emb))
for title, sim in cur.fetchall():
    print(f"  {sim:.3f}  {title}")

# Pattern B: Similarity threshold (minimum quality)
print("\nPattern B: Similarity Threshold (only good matches)")
cur.execute("""
    SELECT title, 1 - (embedding <=> %s::vector) AS sim
    FROM documents
    WHERE 1 - (embedding <=> %s::vector) > 0.3
    ORDER BY embedding <=> %s::vector
    LIMIT 5
""", (query_emb, query_emb, query_emb))
for title, sim in cur.fetchall():
    print(f"  {sim:.3f}  {title}")

# Pattern C: Date range + similarity
print("\nPattern C: Recent documents + Similarity")
cur.execute("""
    SELECT title, created_at, 1 - (embedding <=> %s::vector) AS sim
    FROM documents
    WHERE created_at > NOW() - INTERVAL '30 days'
    ORDER BY embedding <=> %s::vector
    LIMIT 3
""", (query_emb, query_emb))
for title, created, sim in cur.fetchall():
    print(f"  {sim:.3f}  {title}  ({created})")

# Pattern D: Exclude already seen
print("\nPattern D: Exclude documents user already viewed")
already_seen = [1, 3, 5]  # document IDs user already read
cur.execute("""
    SELECT id, title, 1 - (embedding <=> %s::vector) AS sim
    FROM documents
    WHERE id != ALL(%s)
    ORDER BY embedding <=> %s::vector
    LIMIT 3
""", (query_emb, already_seen, query_emb))
# != ALL(%s) excludes all IDs in the list
for doc_id, title, sim in cur.fetchall():
    print(f"  {sim:.3f}  [id={doc_id}]  {title}")

print()
print("pgvector's power: combine ANY SQL filter with vector similarity")
print("This is why PostgreSQL + pgvector often beats standalone vector DBs")

cur.close()
conn.close()
PYEOF
```

---

## What You Learned

| Pattern | SQL | Use Case |
|---------|-----|----------|
| Pre-filter | `WHERE category = 'X' ORDER BY similarity` | User specifies category |
| Similarity threshold | `WHERE similarity > 0.3` | Only return good matches |
| Weighted hybrid | `0.7 * vector + 0.3 * keyword` | Combine meaning + exact match |
| Date filter | `WHERE created_at > interval` | Recent documents only |
| Exclude seen | `WHERE id != ALL(array)` | Recommendations, don't repeat |
