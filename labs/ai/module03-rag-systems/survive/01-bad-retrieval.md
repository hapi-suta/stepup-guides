# SURVIVE 01: The Wrong Documents Problem

## Scenario

Your RAG system has been working great for PostgreSQL questions. Then a user asks: "How do I handle high connection counts?" and the system returns the LOCKS guide instead of the CONNECTION POOLING guide. The answer talks about idle-in-transaction sessions instead of pgBouncer.

The user follows the advice, terminates a bunch of connections, and the application crashes because it needed those connections.

The problem: your retrieval is returning the wrong documents.

---

## The Broken System

Save and run:

```bash
cat > /tmp/survive_bad_retrieval.py << 'PYEOF'
import psycopg2
from sentence_transformers import SentenceTransformer

conn = psycopg2.connect("dbname=postgres host=/tmp")
cur = conn.cursor()
model = SentenceTransformer('all-MiniLM-L6-v2')

def search(query, top_k=3):
    emb = model.encode([query])[0].tolist()
    cur.execute("""
        SELECT source, content, 1 - (embedding <=> %s::vector) AS similarity
        FROM documents
        ORDER BY embedding <=> %s::vector
        LIMIT %s;
    """, (str(emb), str(emb), top_k))
    return cur.fetchall()

# Test cases where retrieval goes WRONG
test_queries = [
    ("How do I handle high connection counts?", "pg-pooling-guide"),
    ("Database backup is failing", "pg-backup-guide"),
    ("How to speed up slow queries?", "pg-indexing-guide"),
    ("My standby server is behind", "pg-monitoring-guide"),
    ("Application getting connection timeout errors", "pg-troubleshooting-guide"),
]

correct = 0
for query, expected_source in test_queries:
    results = search(query)
    top_source = results[0][0]
    top_3_sources = [r[0] for r in results]
    hit_top1 = top_source == expected_source
    hit_top3 = expected_source in top_3_sources

    status = "PASS" if hit_top1 else ("TOP3" if hit_top3 else "FAIL")
    if hit_top1:
        correct += 1

    print(f"[{status}] Q: {query}")
    print(f"  Expected: {expected_source}")
    print(f"  Got top1: {top_source} ({results[0][2]:.4f})")
    if not hit_top1:
        print(f"  Top 3: {top_3_sources}")
    print()

print(f"Top-1 accuracy: {correct}/{len(test_queries)} ({correct/len(test_queries)*100:.0f}%)")
PYEOF
python3 /tmp/survive_bad_retrieval.py
```

---

## Your Mission

The system will likely get some queries wrong. Your job is to improve retrieval accuracy to at least 4/5 correct (top-1) WITHOUT changing the test queries.

Strategies to try:

### Strategy 1: Better chunking
The current documents are single-paragraph summaries. Real docs would have more detail. Add more content to each document to give the embeddings more signal.

### Strategy 2: Query expansion
Before embedding the query, expand it with related terms:
```python
def expand_query(query):
    """Add related terms to improve retrieval."""
    expansions = {
        "connection": "connection pooling pgbouncer max_connections",
        "slow": "performance index sequential scan",
        "backup": "pg_basebackup WAL archive restore",
        "standby": "replication replica lag streaming",
    }
    expanded = query
    for keyword, expansion in expansions.items():
        if keyword.lower() in query.lower():
            expanded += " " + expansion
    return expanded
```

### Strategy 3: Re-ranking
Search top-10 results, then re-rank using a different signal (keyword match, metadata, or a second model).

### Strategy 4: Enriched metadata
Add keywords to document metadata and boost results that match query keywords.

---

## Validation

After your fix:

```
[PASS] Q: How do I handle high connection counts?
  Expected: pg-pooling-guide
  Got top1: pg-pooling-guide
...
Top-1 accuracy: 4/5 (80%) or better
```

<details>
<summary>Runbook (hints, not answers)</summary>

1. **Diagnose first:** Look at the similarity scores. If the wrong doc scores 0.35 and the right doc scores 0.33, the embeddings are nearly identical - your chunks are too similar. Add more distinctive content.

2. **The connection query fails** because "connection" appears in both the pooling guide AND the locks guide (idle-in-transaction holds connections). The fix: add "pgBouncer pool_mode" to the pooling doc or use query expansion to add "pooling pgbouncer" when the user says "connection."

3. **The simplest fix** that works for small doc sets: enrich each document with explicit keywords at the beginning. "Keywords: pgBouncer, connection pooling, pool_mode, transaction mode. ..." The embeddings will weight these terms.

4. **For production:** Use hybrid search (vector + full-text). Full-text search handles exact keyword matches. Vector search handles semantic meaning. Combined, they cover both cases.
</details>
