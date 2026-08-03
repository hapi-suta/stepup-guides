# Build 02: Chunking and Storage

Raw documents are too long to embed as one piece. You need to split them into chunks, embed each chunk, and store them in pgvector. This guide covers chunking strategies and the pgvector setup.

---

## Step 1. Set up PostgreSQL with pgvector

Make sure PostgreSQL 17 is running and pgvector is installed.

On your **Mac terminal**, run:

```bash
brew services start postgresql@17
```

Enable the vector extension:

```bash
/opt/homebrew/opt/postgresql@17/bin/psql postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

Expected output:
```
CREATE EXTENSION
```

Verify it works:

```bash
/opt/homebrew/opt/postgresql@17/bin/psql postgres -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';"
```

Expected output:
```
 extname | extversion
---------+------------
 vector  | 0.8.2
```

---

## Step 2. Create the documents table

This table stores your documents with their embeddings. Think of it as a regular table with one special column - `vector(384)` - that holds the embedding.

```bash
/opt/homebrew/opt/postgresql@17/bin/psql postgres << 'SQL'
DROP TABLE IF EXISTS documents;

CREATE TABLE documents (
    id          SERIAL PRIMARY KEY,
    content     TEXT NOT NULL,
    source      VARCHAR(200),
    chunk_index INTEGER DEFAULT 0,
    metadata    JSONB DEFAULT '{}',
    embedding   vector(384),
    created_at  TIMESTAMP DEFAULT NOW()
);

-- HNSW index for fast similarity search
-- Like a B-tree but for vectors
CREATE INDEX idx_documents_embedding
ON documents USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Regular index for filtering by source
CREATE INDEX idx_documents_source ON documents (source);

SELECT 'Table created' AS status;
SQL
```

Expected output:
```
DROP TABLE
CREATE TABLE
CREATE INDEX
CREATE INDEX
  status
-----------
 Table created
```

- `vector(384)` stores 384-dimensional embeddings (matches our model output)
- `hnsw` is the index type - Hierarchical Navigable Small World graph
- `vector_cosine_ops` tells pgvector to optimize for cosine similarity
- `m = 16` controls the graph connectivity (higher = more accurate, more memory)
- `ef_construction = 64` controls build quality (higher = slower build, better search)
- `source` tracks where each chunk came from (which document/file)
- `chunk_index` tracks the order of chunks within a document

---

## Step 3. Understand chunking strategies

Before storing documents, you need to split them into chunks. The size of your chunks directly affects search quality.

```bash
python3 << 'PYEOF'
# Three chunking strategies compared

text = """PostgreSQL Streaming Replication Guide

Chapter 1: Overview
PostgreSQL streaming replication is a built-in feature that continuously ships WAL records from a primary server to one or more standby servers. This provides high availability and read scaling.

The primary server generates WAL records for every change. These records are streamed to standbys in near real-time. Standbys apply the WAL records to maintain an up-to-date copy.

Chapter 2: Configuration
On the primary server, set these parameters in postgresql.conf:
- wal_level = replica
- max_wal_senders = 10
- wal_keep_size = 1GB

Create a replication user:
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'secure_password';

Update pg_hba.conf to allow the standby to connect:
host replication replicator standby_ip/32 md5

Chapter 3: Setting Up the Standby
Use pg_basebackup to create the initial copy:
pg_basebackup -h primary_ip -D /opt/pgsql/data -U replicator -P -R

The -R flag creates standby.signal and sets primary_conninfo automatically.
Start PostgreSQL on the standby and it will begin replaying WAL records.

Chapter 4: Monitoring
Check replication status on the primary:
SELECT client_addr, state, sent_lsn, replay_lsn, replay_lag FROM pg_stat_replication;

Check standby status:
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();"""


def chunk_by_section(text):
    """Split on chapter/section headers. Best for structured docs."""
    import re
    # re.split() splits text using a pattern (regex).
    # r'\n(?=Chapter \d+:)' means: split at newlines that come right before "Chapter"
    # followed by a number and colon. (?=...) is a "lookahead" - it checks what's ahead
    # without removing it, so "Chapter 2:" stays in the result.
    sections = re.split(r'\n(?=Chapter \d+:)', text)
    # List comprehension: [expression for item in list if condition]
    # This reads like SQL: SELECT s.strip() FROM sections WHERE s is not empty AND len > 20
    # .strip() removes extra whitespace from both ends of the text
    return [s.strip() for s in sections if s.strip() and len(s.strip()) > 20]

def chunk_by_paragraph(text, min_words=15):
    """Split on double newlines. Good for prose."""
    paragraphs = [p.strip() for p in text.split('\n\n') if p.strip()]
    # Merge tiny paragraphs with the next one
    merged = []
    buffer = ""
    for p in paragraphs:
        buffer = (buffer + "\n\n" + p).strip() if buffer else p
        if len(buffer.split()) >= min_words:
            merged.append(buffer)
            buffer = ""
    if buffer:
        merged.append(buffer)
    return merged

def chunk_fixed_size(text, max_words=100, overlap_words=20):
    """Fixed word count with overlap. Most predictable."""
    words = text.split()
    chunks = []
    i = 0
    while i < len(words):
        chunk = ' '.join(words[i:i + max_words])
        if chunk.strip():
            chunks.append(chunk)
        i += max_words - overlap_words
    return chunks


print("=== SECTION-BASED (best for structured docs) ===")
for i, c in enumerate(chunk_by_section(text)):
    print(f"  Chunk {i+1}: {len(c.split()):3d} words | {c[:70]}...")
print()

print("=== PARAGRAPH-BASED (good for prose, min 15 words) ===")
for i, c in enumerate(chunk_by_paragraph(text)):
    print(f"  Chunk {i+1}: {len(c.split()):3d} words | {c[:70]}...")
print()

print("=== FIXED-SIZE (100 words, 20 overlap) ===")
for i, c in enumerate(chunk_fixed_size(text)):
    print(f"  Chunk {i+1}: {len(c.split()):3d} words | {c[:70]}...")
PYEOF
```

Expected output (yours will differ):
```
=== SECTION-BASED (best for structured docs) ===
  Chunk 1:  65 words | Chapter 1: Overview PostgreSQL streaming replication is a built-in ...
  Chunk 2:  49 words | Chapter 2: Configuration On the primary server, set these parameter...
  Chunk 3:  48 words | Chapter 3: Setting Up the Standby Use pg_basebackup to create the i...
  Chunk 4:  26 words | Chapter 4: Monitoring Check replication status on the primary: SELE...

=== PARAGRAPH-BASED (good for prose, min 15 words) ===
  Chunk 1:  38 words | PostgreSQL Streaming Replication Guide Chapter 1: Overview PostgreSQ...
  Chunk 2:  30 words | The primary server generates WAL records for every change...
  ...

=== FIXED-SIZE (100 words, 20 overlap) ===
  Chunk 1: 100 words | PostgreSQL Streaming Replication Guide Chapter 1: Overview PostgreSQ...
  Chunk 2: 100 words | primary server generates WAL records for every change. These records...
  ...
```

**Which to use:**
- **Section-based:** Best when documents have clear headers (runbooks, guides). Each chunk is a self-contained topic.
- **Paragraph-based:** Good for prose (blog posts, reports). Preserves natural thought boundaries.
- **Fixed-size with overlap:** Most predictable size. The overlap prevents splitting a thought right in the middle.

For DBA runbooks and guides, section-based is usually best.

---

## Step 4. Embed and store documents in pgvector

Now let's put it all together - chunk documents, generate embeddings, and store everything in PostgreSQL.

```bash
python3 << 'PYEOF'
import psycopg2
import re
from sentence_transformers import SentenceTransformer

conn = psycopg2.connect("dbname=postgres host=/tmp")
conn.autocommit = True
cur = conn.cursor()

model = SentenceTransformer('all-MiniLM-L6-v2')

# Sample PostgreSQL documentation (8 documents)
documents = {
    "pg-replication-guide": """PostgreSQL streaming replication copies WAL records from a primary server to one or more standby servers in real-time. Configure it by setting wal_level=replica, max_wal_senders=10, and creating a replication slot. Use pg_basebackup to initialize the standby. Monitor with pg_stat_replication.""",

    "pg-monitoring-guide": """To check replication lag, query pg_stat_replication on the primary: SELECT client_addr, state, sent_lsn, replay_lsn, replay_lag FROM pg_stat_replication. For standby status, use pg_last_wal_receive_lsn() and pg_last_xact_replay_timestamp(). A lag over 30 seconds needs investigation.""",

    "pg-vacuum-guide": """VACUUM reclaims storage from dead tuples left behind by UPDATE and DELETE operations. Run VACUUM ANALYZE regularly to also update planner statistics. For heavily updated tables, lower autovacuum_vacuum_scale_factor to 0.05. VACUUM FULL rewrites the entire table and requires an ACCESS EXCLUSIVE lock - use only when necessary.""",

    "pg-pooling-guide": """pgBouncer is a lightweight connection pooler for PostgreSQL. It sits between your application and the database, reusing connections to reduce the overhead of creating new connections for every request. Set pool_mode=transaction for web applications. Monitor active connections with SHOW POOLS and SHOW STATS commands.""",

    "pg-backup-guide": """Use pg_basebackup for full physical backups. For point-in-time recovery (PITR), enable WAL archiving: set archive_mode=on, archive_command to copy WAL files to a safe location. To restore, stop PostgreSQL, restore the base backup, create recovery.signal, set restore_command, and start PostgreSQL.""",

    "pg-indexing-guide": """PostgreSQL indexes speed up queries by avoiding full table scans. B-tree is the default and works for equality and range queries. GIN indexes are best for full-text search and array columns. BRIN indexes work well for naturally ordered data like timestamps. Always use CREATE INDEX CONCURRENTLY in production to avoid locking the table.""",

    "pg-troubleshooting-guide": """Connection refused errors usually mean PostgreSQL is not running or pg_hba.conf blocks the connection. Check service status first: systemctl status postgresql. Then verify pg_hba.conf allows your client IP and authentication method. For timeout errors, check max_connections and whether connection pooling is configured.""",

    "pg-locks-guide": """PostgreSQL locks prevent concurrent transactions from conflicting. The most common problem is idle-in-transaction sessions that hold locks indefinitely, blocking other queries. Set idle_in_transaction_session_timeout to automatically kill them. To find blocking queries: SELECT blocked.pid, blocker.pid, blocked.query FROM pg_stat_activity blocked JOIN pg_locks ...""",
}

# Clear existing data
cur.execute("DELETE FROM documents;")

# Chunk, embed, and store
total_chunks = 0
for source, content in documents.items():
    # Simple paragraph chunking for these short docs
    chunks = [content]  # Each doc is already one good chunk

    embeddings = model.encode(chunks)

    # zip(chunks, embeddings) pairs each chunk with its embedding (like joining by position).
    # enumerate() adds a counter (i = 0, 1, 2...) - like ROW_NUMBER().
    for i, (chunk, emb) in enumerate(zip(chunks, embeddings)):
        cur.execute(
            """INSERT INTO documents (content, source, chunk_index, embedding)
               VALUES (%s, %s, %s, %s::vector)""",
            (chunk, source, i, str(emb.tolist()))
        )
        total_chunks += 1

print(f"Stored {total_chunks} chunks from {len(documents)} documents")

# Verify
cur.execute("SELECT source, LENGTH(content), chunk_index FROM documents ORDER BY source;")
print("\nStored documents:")
for row in cur.fetchall():
    print(f"  {row[0]:30s} | {row[1]:4d} chars | chunk {row[2]}")

cur.close()
conn.close()
PYEOF
```

Expected output (yours will differ):
```
Stored 8 chunks from 8 documents

Stored documents:
  pg-backup-guide                |  345 chars | chunk 0
  pg-indexing-guide               |  347 chars | chunk 0
  pg-locks-guide                  |  390 chars | chunk 0
  pg-monitoring-guide             |  305 chars | chunk 0
  pg-pooling-guide                |  340 chars | chunk 0
  pg-replication-guide            |  298 chars | chunk 0
  pg-troubleshooting-guide        |  352 chars | chunk 0
  pg-vacuum-guide                 |  340 chars | chunk 0
```

---

## Step 5. Search with pgvector

Now the powerful part - semantic search in SQL.

```bash
python3 << 'PYEOF'
import psycopg2
from sentence_transformers import SentenceTransformer

conn = psycopg2.connect("dbname=postgres host=/tmp")
cur = conn.cursor()
model = SentenceTransformer('all-MiniLM-L6-v2')

def search(query, top_k=3):
    query_emb = model.encode([query])[0].tolist()
    cur.execute("""
        SELECT content, source, 1 - (embedding <=> %s::vector) AS similarity
        FROM documents
        ORDER BY embedding <=> %s::vector
        LIMIT %s;
    """, (str(query_emb), str(query_emb), top_k))
    return cur.fetchall()

queries = [
    "How do I fix replication lag?",
    "My application can't connect to the database",
    "The orders table is very bloated",
    "How do I create an index without downtime?",
]

for q in queries:
    print(f"Q: {q}")
    print("-" * 60)
    results = search(q)
    for content, source, sim in results:
        print(f"  [{sim:.4f}] {source}")
        print(f"           {content[:100]}...")
    print()
PYEOF
```

Expected output (yours will differ):
```
Q: How do I fix replication lag?
------------------------------------------------------------
  [0.6413] pg-monitoring-guide
           To check replication lag, query pg_stat_replication on the primary...
  [0.4190] pg-replication-guide
           PostgreSQL streaming replication copies WAL records from a primary...
  [0.1994] pg-locks-guide
           PostgreSQL locks prevent concurrent transactions from conflicting...

Q: My application can't connect to the database
------------------------------------------------------------
  [0.4202] pg-troubleshooting-guide
           Connection refused errors usually mean PostgreSQL is not running...
  [0.2769] pg-pooling-guide
           pgBouncer is a lightweight connection pooler for PostgreSQL...
  [0.1286] pg-locks-guide
           PostgreSQL locks prevent concurrent transactions from conflicting...

Q: The orders table is very bloated
------------------------------------------------------------
  [0.4856] pg-vacuum-guide
           VACUUM reclaims storage from dead tuples left behind by UPDATE...
  [0.2134] pg-indexing-guide
           PostgreSQL indexes speed up queries by avoiding full table scans...
  ...

Q: How do I create an index without downtime?
------------------------------------------------------------
  [0.5912] pg-indexing-guide
           PostgreSQL indexes speed up queries... CREATE INDEX CONCURRENTLY...
  ...
```

Notice:
- "fix replication lag" found the monitoring guide AND the replication guide
- "can't connect" found the troubleshooting guide AND connection pooling (both relevant)
- "table is bloated" found the vacuum guide (even though "bloated" doesn't appear exactly)
- "index without downtime" found the indexing guide that mentions CONCURRENTLY

This is pure SQL - `ORDER BY embedding <=> query_vector`. You can add WHERE clauses, JOIN with other tables, filter by source, combine with full-text search. It's PostgreSQL.

---

## What You Learned

| Concept | What It Does | SQL Equivalent |
|---------|-------------|---------------|
| `vector(384)` column | Stores embeddings | Like `FLOAT8[]` but optimized |
| `<=>` operator | Cosine distance between vectors | Like `<` for ordering |
| HNSW index | Fast approximate nearest neighbor | Like B-tree for vectors |
| Chunking | Split docs into searchable pieces | Like normalizing a table |
| `ORDER BY embedding <=> query` | Similarity search | `ORDER BY distance ASC LIMIT k` |
