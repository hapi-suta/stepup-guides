# Build 01: pgvector Setup and Basics

pgvector turns PostgreSQL into a vector database. You get vector search without leaving your existing database infrastructure. This guide covers installation, basic operations, and your first similarity searches.

---

## Step 1. Verify pgvector is installed

On your **Mac terminal**, run:

```bash
psql -h localhost -p 5432 -U $(whoami) -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

This creates the pgvector extension. If pgvector isn't installed, install it:

```bash
brew install pgvector
```

Then restart PostgreSQL and try again.

Verify it works:

```bash
psql -h localhost -p 5432 -U $(whoami) -d postgres -c "SELECT extversion FROM pg_extension WHERE extname = 'vector';"
```

Expected output:

```
 extversion
------------
 0.8.2
```

---

## Step 2. Create a vector table

On your **Mac terminal**, run:

```bash
psql -h localhost -p 5432 -U $(whoami) -d postgres << 'SQL'
-- Drop if exists (for re-running this guide)
DROP TABLE IF EXISTS documents;

-- Create a table with a vector column
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT NOT NULL,
    embedding vector(384),  -- 384-dimensional embedding vector
    created_at TIMESTAMP DEFAULT NOW()
);
-- vector(384) stores a vector with exactly 384 dimensions
-- 384 is the output size of the 'all-MiniLM-L6-v2' model (small, fast)
-- Other common sizes: 768 (BERT), 1536 (OpenAI ada-002), 3072 (OpenAI text-embedding-3-large)

COMMENT ON COLUMN documents.embedding IS 'Sentence embedding from all-MiniLM-L6-v2';

-- Check the table
\d documents
SQL
```

Expected output (yours will differ):

```
                                      Table "public.documents"
   Column   |            Type             | Collation | Nullable |                Default
------------+-----------------------------+-----------+----------+---------------------------------------
 id         | integer                     |           | not null | nextval('documents_id_seq'::regclass)
 title      | text                        |           | not null |
 content    | text                        |           | not null |
 category   | text                        |           | not null |
 embedding  | vector(384)                 |           |          |
 created_at | timestamp without time zone |           |          | now()
```

---

## Step 3. Generate embeddings and insert data

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2  # psycopg2 is the PostgreSQL driver for Python (like sqlplus for Oracle, psql for Postgres)
import numpy as np  # numpy for math operations, "as np" is a short alias

# Try to use sentence-transformers for real embeddings
try:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('all-MiniLM-L6-v2')
    # all-MiniLM-L6-v2: small (80MB), fast, 384 dimensions
    # Good for semantic search and similarity
    USE_REAL_EMBEDDINGS = True
    print("Using real embeddings from all-MiniLM-L6-v2")
except ImportError:
    USE_REAL_EMBEDDINGS = False
    print("sentence-transformers not installed, using random vectors")
    print("Install with: pip3 install sentence-transformers")

# Database documentation
docs = [
    ("PostgreSQL Replication Setup", "Configure streaming replication between primary and standby servers using pg_basebackup and recovery.conf", "replication"),
    ("Replication Lag Monitoring", "Monitor replication lag using pg_stat_replication view and set up alerts for lag exceeding threshold", "replication"),
    ("WAL Archiving Configuration", "Set up continuous WAL archiving to S3 or local storage for point-in-time recovery", "backup"),
    ("pg_basebackup Usage", "Create a base backup of the database cluster for standby initialization or disaster recovery", "backup"),
    ("Connection Pooling with PgBouncer", "Deploy PgBouncer in front of PostgreSQL to manage connection pooling and reduce overhead", "performance"),
    ("Query Performance Tuning", "Use EXPLAIN ANALYZE to identify slow queries and optimize with proper indexes", "performance"),
    ("Index Selection Guide", "Choose between B-tree, GIN, GiST, and BRIN indexes based on query patterns", "performance"),
    ("PostgreSQL Backup Strategies", "Compare pg_dump, pg_basebackup, and Barman for backup and recovery", "backup"),
    ("VACUUM and Autovacuum Tuning", "Configure autovacuum parameters to prevent table bloat and maintain performance", "maintenance"),
    ("pg_stat_statements Setup", "Install and configure pg_stat_statements to track query performance statistics", "monitoring"),
    ("SSL Configuration for PostgreSQL", "Enable SSL/TLS encryption for client connections to the database server", "security"),
    ("Role-Based Access Control", "Set up PostgreSQL roles, permissions, and row-level security for multi-tenant access", "security"),
    ("Logical Replication Setup", "Configure logical replication for selective table replication and zero-downtime upgrades", "replication"),
    ("Partitioning Large Tables", "Use declarative partitioning to manage large tables and improve query performance", "performance"),
    ("Disaster Recovery Planning", "Design and test a disaster recovery plan with RPO and RTO targets", "backup"),
]

# Generate embeddings
if USE_REAL_EMBEDDINGS:
    # List comprehension with _ (underscore) = throw away values you don't need.
    # [content for _, content, _ in docs] means: from each 3-item tuple,
    # keep only the second item (content), ignore first and third.
    # DBA analogy: SELECT content FROM docs (ignoring the other columns)
    contents = [content for _, content, _ in docs]
    embeddings = model.encode(contents)
    # model.encode() converts text to embedding vectors
    # Returns numpy array of shape [num_texts, 384]
else:
    np.random.seed(42)
    embeddings = np.random.randn(len(docs), 384).astype(np.float32)

# Connect to PostgreSQL
import os
conn = psycopg2.connect(
    host="localhost",
    port=5432,
    user=os.environ.get("USER"),
    dbname="postgres"
)
cur = conn.cursor()

# Clear existing data
cur.execute("DELETE FROM documents")

# Insert documents with embeddings
for i, (title, content, category) in enumerate(docs):
    embedding = embeddings[i].tolist()
    # .tolist() converts numpy array to Python list (required by psycopg2)
    cur.execute(
        "INSERT INTO documents (title, content, category, embedding) VALUES (%s, %s, %s, %s)",
        (title, content, category, str(embedding))
        # str(embedding) converts list to string format pgvector expects: '[0.1, 0.2, ...]'
    )

conn.commit()
print(f"Inserted {len(docs)} documents with {embeddings.shape[1]}-dimensional embeddings")

# Verify
cur.execute("SELECT count(*), avg(vector_dims(embedding)) FROM documents")
# Tuple unpacking: fetchone() returns one row as a tuple (like a pair of values).
# count, dims = cur.fetchone() catches each column in its own variable.
# DBA analogy: SELECT count, dims INTO v_count, v_dims FROM ...
count, dims = cur.fetchone()
print(f"Table has {count} rows with {int(dims)}-dimensional vectors")

cur.close()
conn.close()
PYEOF
```

Expected output (yours will differ):

```
Using real embeddings from all-MiniLM-L6-v2
Inserted 15 documents with 384-dimensional embeddings
Table has 15 rows with 384-dimensional vectors
```

If you don't have sentence-transformers installed:

```bash
pip3 install sentence-transformers
```

---

## Step 4. Your first vector search

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

def search(query_text, top_k=5):
    """Search for documents similar to the query."""
    if USE_REAL:
        query_embedding = model.encode([query_text])[0].tolist()
        # encode() returns [1, 384], [0] gets the single vector, .tolist() for SQL
    else:
        np.random.seed(hash(query_text) % 2**32)
        query_embedding = np.random.randn(384).tolist()

    cur.execute("""
        SELECT title, category, content,
               1 - (embedding <=> %s::vector) AS similarity
               -- <=> is the cosine distance operator
               -- 1 - distance = similarity (1.0 = identical, 0.0 = unrelated)
        FROM documents
        ORDER BY embedding <=> %s::vector
        -- ORDER BY distance ascending = most similar first
        LIMIT %s
    """, (str(query_embedding), str(query_embedding), top_k))
    # %s::vector casts the string to a vector type

    return cur.fetchall()

# Search queries
queries = [
    "How do I set up a standby server?",
    "My database is running slow",
    "How to encrypt database connections?",
    "backup my database to the cloud",
]

for query in queries:
    print(f"\nQuery: '{query}'")
    print("-" * 60)
    results = search(query, top_k=3)
    for title, category, content, similarity in results:
        print(f"  {similarity:.3f}  [{category:>12s}]  {title}")

cur.close()
conn.close()

print()
print("The model understands MEANING, not just keywords:")
print("  'standby server' matches 'replication' docs")
print("  'running slow' matches 'performance' docs")
print("  'encrypt connections' matches 'SSL' docs")
PYEOF
```

Expected output (yours will differ):

```
Query: 'How do I set up a standby server?'
------------------------------------------------------------
  0.721  [ replication]  PostgreSQL Replication Setup
  0.654  [ replication]  Logical Replication Setup
  0.598  [      backup]  pg_basebackup Usage

Query: 'My database is running slow'
------------------------------------------------------------
  0.682  [ performance]  Query Performance Tuning
  0.645  [ performance]  Connection Pooling with PgBouncer
  0.612  [ performance]  VACUUM and Autovacuum Tuning
```

---

## Step 5. Distance operators explained

On your **Mac terminal**, run:

```bash
psql -h localhost -p 5432 -U $(whoami) -d postgres << 'SQL'
-- pgvector provides three distance operators:

-- 1. <=> Cosine distance (most common for text)
-- Range: 0 to 2 (0 = identical, 2 = opposite)
SELECT
    a.title AS doc_a,
    b.title AS doc_b,
    a.embedding <=> b.embedding AS cosine_distance,
    1 - (a.embedding <=> b.embedding) AS cosine_similarity
FROM documents a, documents b
WHERE a.id = 1 AND b.id IN (2, 3, 5)
ORDER BY cosine_distance;

-- 2. <-> L2 (Euclidean) distance
-- Range: 0 to infinity (0 = identical)
-- SELECT a.embedding <-> b.embedding AS l2_distance ...

-- 3. <#> Inner product distance (negative inner product)
-- Use for maximum inner product search
-- SELECT a.embedding <#> b.embedding AS inner_product_distance ...

-- Which to use?
-- Text/embeddings: <=> (cosine) - handles different vector magnitudes
-- Numeric features: <-> (L2) - when magnitude matters
-- Recommendations: <#> (inner product) - when vectors are already normalized
SQL
```

---

## What You Learned

| Concept | What It Does | SQL Equivalent |
|---------|-------------|---------------|
| `vector(384)` data type | Stores 384-dimensional vectors | Like `numeric[]` but optimized |
| `<=>` operator | Cosine distance between vectors | Like `<>` but for similarity |
| `ORDER BY embedding <=> query` | Sort by similarity | Like `ORDER BY distance ASC` |
| `1 - (a <=> b)` | Convert distance to similarity | 1.0 = identical, 0.0 = unrelated |
| Sentence embedding | Convert text to vector | Like hashing but preserves meaning |
