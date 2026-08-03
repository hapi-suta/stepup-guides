# SURVIVE 02: Stale Embeddings

Your RAG system worked perfectly when deployed. Six months later, users complain that searches return outdated information. The documents were updated but the embeddings weren't regenerated - the vector index is searching on old content.

---

## The Scenario

A team maintains a PostgreSQL documentation knowledge base. They update documents regularly (new PostgreSQL versions, new procedures). But the embedding column wasn't updated when content changed. The vector search finds documents based on their OLD content, returning stale or incorrect information.

---

## Step 1. See the problem

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import numpy as np
from datetime import datetime, timedelta

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

# Setup: table with embedding tracking
cur.execute("DROP TABLE IF EXISTS kb_docs")
cur.execute("""
    CREATE TABLE kb_docs (
        id SERIAL PRIMARY KEY,
        title TEXT,
        content TEXT,
        embedding vector(384),
        content_updated_at TIMESTAMP DEFAULT NOW(),
        embedding_updated_at TIMESTAMP DEFAULT NOW()
    )
""")

# Insert documents with current embeddings
docs = [
    ("Replication Setup", "Configure streaming replication in PostgreSQL 14 using recovery.conf"),
    ("Backup Guide", "Use pg_basebackup for creating base backups in PostgreSQL 14"),
    ("Connection Pooling", "Deploy PgBouncer 1.17 for connection pooling"),
]

for title, content in docs:
    emb = str(get_embedding(content))
    cur.execute("""
        INSERT INTO kb_docs (title, content, embedding, content_updated_at, embedding_updated_at)
        VALUES (%s, %s, %s, NOW(), NOW())
    """, (title, content, emb))
conn.commit()

# Simulate: content is updated but embedding is NOT
# PostgreSQL 14 -> PostgreSQL 17, recovery.conf -> standby.signal
print("Simulating document updates WITHOUT embedding refresh...")
cur.execute("""
    UPDATE kb_docs
    SET content = 'Configure streaming replication in PostgreSQL 17 using standby.signal',
        content_updated_at = NOW()
    WHERE title = 'Replication Setup'
""")
# NOTE: embedding was NOT updated! It still reflects the old content.

cur.execute("""
    UPDATE kb_docs
    SET content = 'Use pg_basebackup for creating base backups in PostgreSQL 17 with compression',
        content_updated_at = NOW()
    WHERE title = 'Backup Guide'
""")
conn.commit()

# Check staleness
cur.execute("""
    SELECT title,
           content_updated_at,
           embedding_updated_at,
           content_updated_at > embedding_updated_at AS is_stale
    FROM kb_docs
""")

print()
print("Document Freshness Check:")
print(f"{'Title':25s}  {'Stale?':>7s}")
print("-" * 35)
for title, content_time, emb_time, stale in cur.fetchall():
    print(f"{title:25s}  {'STALE' if stale else 'OK':>7s}")

# Show the problem: search for PostgreSQL 17
query = "How to set up replication in PostgreSQL 17?"
query_emb = str(get_embedding(query))

cur.execute("""
    SELECT title, content,
           1 - (embedding <=> %s::vector) AS similarity
    FROM kb_docs
    ORDER BY embedding <=> %s::vector
    LIMIT 3
""", (query_emb, query_emb))

print(f"\nSearch: '{query}'")
print("-" * 60)
for title, content, sim in cur.fetchall():
    print(f"  {sim:.3f}  {title}")
    print(f"         Content: {content[:60]}...")

print()
print("PROBLEM: The search uses OLD embeddings")
print("The embedding for 'Replication Setup' was computed from the PG14 content")
print("but the document now talks about PG17. The similarity score is wrong.")

cur.close()
conn.close()
PYEOF
```

---

## Step 2. The fix - embedding freshness system

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

# Fix: refresh stale embeddings
print("Refreshing stale embeddings...")
cur.execute("""
    SELECT id, content FROM kb_docs
    WHERE content_updated_at > embedding_updated_at
""")
stale_docs = cur.fetchall()
print(f"Found {len(stale_docs)} stale documents")

for doc_id, content in stale_docs:
    new_emb = str(get_embedding(content))
    cur.execute("""
        UPDATE kb_docs
        SET embedding = %s, embedding_updated_at = NOW()
        WHERE id = %s
    """, (new_emb, doc_id))
    print(f"  Refreshed: id={doc_id}")

conn.commit()

# Verify: search again
query = "How to set up replication in PostgreSQL 17?"
query_emb = str(get_embedding(query))

cur.execute("""
    SELECT title, content,
           1 - (embedding <=> %s::vector) AS similarity
    FROM kb_docs
    ORDER BY embedding <=> %s::vector
    LIMIT 3
""", (query_emb, query_emb))

print(f"\nAfter refresh - Search: '{query}'")
print("-" * 60)
for title, content, sim in cur.fetchall():
    print(f"  {sim:.3f}  {title}")
    print(f"         Content: {content[:60]}...")

print()
print("Prevention checklist:")
print("  1. Always track content_updated_at and embedding_updated_at")
print("  2. Run a refresh job daily: find stale docs, regenerate embeddings")
print("  3. Alert when > 5% of embeddings are stale")
print("  4. After model upgrade: regenerate ALL embeddings")
print("  5. Never mix embeddings from different models in the same column")

cur.close()
conn.close()
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Content updated without embedding refresh | Search returns outdated results | Track content_updated_at vs embedding_updated_at |
| No staleness monitoring | Don't know embeddings are stale | Daily check: WHERE content_updated > embedding_updated |
| Mixed embedding models | Similarity scores are meaningless | Track embedding_model column, never mix |
| No refresh automation | Manual process, always forgotten | Scheduled job to refresh stale embeddings |
