# Build 03: Retrieval and Generation

This is where it all comes together. You search pgvector for relevant documents, then feed them to Claude to generate a grounded answer. This is the complete RAG pipeline.

---

## Step 1. The RAG function

This function takes a question, searches pgvector, and asks Claude to answer using only the retrieved documents.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import anthropic
from sentence_transformers import SentenceTransformer

# Setup
conn = psycopg2.connect("dbname=postgres host=/tmp")
cur = conn.cursor()
model = SentenceTransformer('all-MiniLM-L6-v2')
claude = anthropic.Anthropic()

def rag_query(question: str, top_k: int = 3) -> dict:
    """Complete RAG pipeline: retrieve from pgvector, generate with Claude."""

    # Step 1: Embed the question
    query_emb = model.encode([question])[0].tolist()

    # Step 2: Search pgvector for relevant documents
    cur.execute("""
        SELECT content, source, 1 - (embedding <=> %s::vector) AS similarity
        FROM documents
        ORDER BY embedding <=> %s::vector
        LIMIT %s;
    """, (str(query_emb), str(query_emb), top_k))
    results = cur.fetchall()

    # Step 3: Build the context from retrieved documents
    context_parts = []
    sources_used = []
    for content, source, sim in results:
        context_parts.append(f"[Source: {source}, Relevance: {sim:.2f}]\n{content}")
        sources_used.append({"source": source, "similarity": round(sim, 4)})

    context = "\n\n---\n\n".join(context_parts)

    # Step 4: Generate answer with Claude
    system = """You are a PostgreSQL DBA assistant. Answer questions using ONLY the context provided below.

Rules:
- Only use information from the provided context
- If the context doesn't contain enough information, say so
- Cite which source document you're using: [source: document-name]
- Be specific and actionable
- If recommending a command, include the exact SQL or shell command"""

    user_msg = f"""Context:
{context}

---

Question: {question}"""

    msg = claude.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=400,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": user_msg}]
    )

    return {
        "question": question,
        "answer": msg.content[0].text,
        "sources": sources_used,
        "tokens_used": msg.usage.input_tokens + msg.usage.output_tokens,
    }


# Test it
result = rag_query("How do I check if replication is working?")

print(f"Q: {result['question']}")
print(f"\nA: {result['answer']}")
print(f"\nSources used:")
for s in result['sources']:
    print(f"  [{s['similarity']:.4f}] {s['source']}")
print(f"\nTokens used: {result['tokens_used']}")

conn.close()
PYEOF
```

Expected output (yours will differ):
```
Q: How do I check if replication is working?

A: To check if replication is working, run this query on the primary
server [source: pg-monitoring-guide]:

SELECT client_addr, state, sent_lsn, replay_lsn, replay_lag
FROM pg_stat_replication;

This shows all connected standbys with their current state and lag.
A healthy replica shows state='streaming' and minimal replay_lag.

On the standby, you can verify it's receiving WAL with
[source: pg-monitoring-guide]:

SELECT pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();

If replay_lag exceeds 30 seconds, investigate network latency,
standby I/O performance, or long-running queries on the standby.

Sources used:
  [0.6413] pg-monitoring-guide
  [0.4190] pg-replication-guide
  [0.1994] pg-locks-guide

Tokens used: ~850
```

That answer is grounded in YOUR documentation. Claude cited the source documents. It included the exact SQL commands from your runbooks. This is RAG.

---

## Step 2. Handle "I don't know"

A critical feature: the AI should admit when the context doesn't contain the answer instead of hallucinating.

```bash
python3 << 'PYEOF'
import psycopg2
import anthropic
from sentence_transformers import SentenceTransformer

conn = psycopg2.connect("dbname=postgres host=/tmp")
cur = conn.cursor()
model = SentenceTransformer('all-MiniLM-L6-v2')
claude = anthropic.Anthropic()

def rag_query(question, top_k=3, min_similarity=0.25):
    """RAG with similarity threshold - filters out irrelevant results."""
    query_emb = model.encode([question])[0].tolist()

    cur.execute("""
        SELECT content, source, 1 - (embedding <=> %s::vector) AS similarity
        FROM documents
        WHERE 1 - (embedding <=> %s::vector) > %s
        ORDER BY embedding <=> %s::vector
        LIMIT %s;
    """, (str(query_emb), str(query_emb), min_similarity, str(query_emb), top_k))
    results = cur.fetchall()

    if not results:
        return {
            "question": question,
            "answer": "I don't have documentation about this topic. The available documentation covers: replication, monitoring, vacuum, connection pooling, backups, indexing, troubleshooting, and locks.",
            "sources": [],
            "grounded": False,
        }

    context = "\n\n---\n\n".join(
        f"[Source: {src}, Relevance: {sim:.2f}]\n{content}"
        for content, src, sim in results
    )

    system = """You are a PostgreSQL DBA assistant. Answer using ONLY the provided context.
If the context doesn't fully answer the question, say what you CAN answer and what's missing.
Always cite sources with [source: name]."""

    msg = claude.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=300,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": f"Context:\n{context}\n\n---\nQuestion: {question}"}]
    )

    return {
        "question": question,
        "answer": msg.content[0].text,
        "sources": [{"source": src, "similarity": round(sim, 4)} for _, src, sim in results],
        "grounded": True,
    }

# Test with in-scope question
print("=== In-scope question ===")
r1 = rag_query("How do I reduce table bloat?")
print(f"Q: {r1['question']}")
print(f"A: {r1['answer'][:200]}...")
print(f"Grounded: {r1['grounded']}")
print()

# Test with out-of-scope question
print("=== Out-of-scope question ===")
r2 = rag_query("How do I deploy a Kubernetes cluster?")
print(f"Q: {r2['question']}")
print(f"A: {r2['answer']}")
print(f"Grounded: {r2['grounded']}")
print()

# Test with partially relevant question
print("=== Partially relevant question ===")
r3 = rag_query("How do I set up logical replication with pglogical?")
print(f"Q: {r3['question']}")
print(f"A: {r3['answer'][:200]}...")
print(f"Grounded: {r3['grounded']}")

conn.close()
PYEOF
```

Expected output (yours will differ):
```
=== In-scope question ===
Q: How do I reduce table bloat?
A: To reduce table bloat [source: pg-vacuum-guide]: Run VACUUM ANALYZE
to reclaim dead tuples. For heavily updated tables, lower
autovacuum_vacuum_scale_factor to 0.05...
Grounded: True

=== Out-of-scope question ===
Q: How do I deploy a Kubernetes cluster?
A: I don't have documentation about this topic. The available
documentation covers: replication, monitoring, vacuum, connection
pooling, backups, indexing, troubleshooting, and locks.
Grounded: False

=== Partially relevant question ===
Q: How do I set up logical replication with pglogical?
A: The documentation covers streaming replication [source:
pg-replication-guide] but doesn't include information about logical
replication or pglogical specifically...
Grounded: True
```

Three important behaviors:
1. **In-scope:** Answers from documentation with citations
2. **Out-of-scope:** Admits it doesn't know instead of hallucinating
3. **Partially relevant:** Uses what it has and tells you what's missing

The `min_similarity=0.25` threshold filters out irrelevant results. Too low and you get noise. Too high and you miss relevant docs. Tune this for your data.

---

## Step 3. Add metadata filtering

Real RAG systems filter by document type, recency, or category before searching embeddings. This is where pgvector's PostgreSQL foundation shines - you can combine vector search with regular SQL.

```bash
python3 << 'PYEOF'
import psycopg2
from sentence_transformers import SentenceTransformer

conn = psycopg2.connect("dbname=postgres host=/tmp")
conn.autocommit = True
cur = conn.cursor()
model = SentenceTransformer('all-MiniLM-L6-v2')

# Update metadata on existing documents
metadata_map = {
    'pg-replication-guide': '{"category": "ha", "priority": "high"}',
    'pg-monitoring-guide': '{"category": "monitoring", "priority": "high"}',
    'pg-vacuum-guide': '{"category": "maintenance", "priority": "medium"}',
    'pg-pooling-guide': '{"category": "performance", "priority": "medium"}',
    'pg-backup-guide': '{"category": "backup", "priority": "high"}',
    'pg-indexing-guide': '{"category": "performance", "priority": "medium"}',
    'pg-troubleshooting-guide': '{"category": "troubleshooting", "priority": "high"}',
    'pg-locks-guide': '{"category": "troubleshooting", "priority": "high"}',
}

for source, meta in metadata_map.items():
    cur.execute("UPDATE documents SET metadata = %s::jsonb WHERE source = %s", (meta, source))

print("Metadata updated")
print()

# Search with category filter
query = "database performance is bad"
query_emb = model.encode([query])[0].tolist()

print("=== All categories ===")
cur.execute("""
    SELECT source, metadata->>'category' AS cat, 1 - (embedding <=> %s::vector) AS sim
    FROM documents
    ORDER BY embedding <=> %s::vector LIMIT 3;
""", (str(query_emb), str(query_emb)))
for row in cur.fetchall():
    print(f"  [{row[2]:.4f}] {row[0]} ({row[1]})")

print()
print("=== Performance category only ===")
cur.execute("""
    SELECT source, metadata->>'category' AS cat, 1 - (embedding <=> %s::vector) AS sim
    FROM documents
    WHERE metadata->>'category' = 'performance'
    ORDER BY embedding <=> %s::vector LIMIT 3;
""", (str(query_emb), str(query_emb)))
for row in cur.fetchall():
    print(f"  [{row[2]:.4f}] {row[0]} ({row[1]})")

print()
print("=== High priority only ===")
cur.execute("""
    SELECT source, metadata->>'category' AS cat, metadata->>'priority' AS pri,
           1 - (embedding <=> %s::vector) AS sim
    FROM documents
    WHERE metadata->>'priority' = 'high'
    ORDER BY embedding <=> %s::vector LIMIT 3;
""", (str(query_emb), str(query_emb)))
for row in cur.fetchall():
    print(f"  [{row[3]:.4f}] {row[0]} ({row[1]}, {row[2]})")

conn.close()
PYEOF
```

Expected output (yours will differ):
```
Metadata updated

=== All categories ===
  [0.3456] pg-indexing-guide (performance)
  [0.3123] pg-vacuum-guide (maintenance)
  [0.2987] pg-pooling-guide (performance)

=== Performance category only ===
  [0.3456] pg-indexing-guide (performance)
  [0.2987] pg-pooling-guide (performance)

=== High priority only ===
  [0.2345] pg-monitoring-guide (monitoring, high)
  [0.2134] pg-troubleshooting-guide (troubleshooting, high)
  [0.1987] pg-replication-guide (ha, high)
```

This is WHERE pgvector beats standalone vector databases. You can:
- Filter by category (`WHERE metadata->>'category' = 'performance'`)
- Filter by priority, date, author, version - any metadata
- JOIN with other tables (users, permissions, teams)
- Combine vector search with full-text search
- Use standard PostgreSQL JSONB operators on metadata

It's just SQL.

---

## Step 4. The complete RAG pipeline script

Here's a production-ready script that ties everything together. Save it for reuse.

```bash
cat > ~/Projects/AItech/labs/ai/module03-rag-systems/build/rag_pipeline.py << 'PYEOF'
"""
Complete RAG Pipeline using pgvector + Claude
Usage: python3 rag_pipeline.py "your question here"
"""
import sys
import psycopg2
import anthropic
from sentence_transformers import SentenceTransformer


# === PYTHON CLASSES - QUICK INTRO ===
# A class is like CREATE TYPE in PostgreSQL - it defines a blueprint.
# class RAGPipeline:           <- the blueprint name
#     def __init__(self, ...): <- setup code, runs when you create one
#                                 like DEFAULT values on a table
#     self.conn = ...          <- "self" means "this instance"
#                                 like NEW.column in a trigger function
# To create one: pipeline = RAGPipeline(...)
# This runs __init__ automatically, like INSERT triggers defaults.
class RAGPipeline:
    def __init__(self, db_name="postgres", model_name="all-MiniLM-L6-v2"):
        self.conn = psycopg2.connect(f"dbname={db_name} host=/tmp")
        self.cur = self.conn.cursor()
        self.embedder = SentenceTransformer(model_name)
        self.claude = anthropic.Anthropic()

    def search(self, query: str, top_k: int = 3, min_sim: float = 0.20) -> list:
        """Search pgvector for relevant documents."""
        emb = self.embedder.encode([query])[0].tolist()
        self.cur.execute("""
            SELECT content, source, 1 - (embedding <=> %s::vector) AS similarity
            FROM documents
            WHERE 1 - (embedding <=> %s::vector) > %s
            ORDER BY embedding <=> %s::vector
            LIMIT %s;
        """, (str(emb), str(emb), min_sim, str(emb), top_k))
        return self.cur.fetchall()

    def generate(self, question: str, context_docs: list) -> str:
        """Generate answer using Claude with retrieved context."""
        if not context_docs:
            return "I don't have relevant documentation to answer this question."

        context = "\n\n---\n\n".join(
            f"[Source: {src}]\n{content}"
            for content, src, sim in context_docs
        )

        msg = self.claude.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=400,
            temperature=0,
            system="""You are a PostgreSQL DBA assistant. Answer using ONLY the provided context.
Cite sources with [source: name]. Be specific and include exact commands when relevant.
If the context doesn't fully answer the question, say what's missing.""",
            messages=[{"role": "user", "content": f"Context:\n{context}\n\n---\nQuestion: {question}"}]
        )
        return msg.content[0].text

    def query(self, question: str) -> None:
        """Full RAG pipeline: search -> generate -> display."""
        print(f"\nQ: {question}")
        print("=" * 60)

        docs = self.search(question)

        print(f"\nRetrieved {len(docs)} documents:")
        for content, source, sim in docs:
            print(f"  [{sim:.4f}] {source}")

        print(f"\nAnswer:")
        answer = self.generate(question, docs)
        print(answer)
        print()

    def close(self):
        self.cur.close()
        self.conn.close()


# __name__ == "__main__" means "only run this code if the file is executed directly."
# If someone imports this file from another script, this block is skipped.
# Think of it as: "run this only when I call the script, not when I load the library."
if __name__ == "__main__":
    rag = RAGPipeline()

    if len(sys.argv) > 1:
        question = " ".join(sys.argv[1:])
        rag.query(question)
    else:
        # Interactive mode
        print("RAG Pipeline Ready (type 'quit' to exit)")
        print("-" * 40)
        while True:
            q = input("\nQuestion: ").strip()
            if q.lower() in ('quit', 'exit', 'q'):
                break
            if q:
                rag.query(q)

    rag.close()
PYEOF
echo "Saved: ~/Projects/AItech/labs/ai/module03-rag-systems/build/rag_pipeline.py"
echo "Run: python3 ~/Projects/AItech/labs/ai/module03-rag-systems/build/rag_pipeline.py 'your question'"
```

---

## What You Learned

| Concept | What It Does | Production Importance |
|---------|-------------|----------------------|
| RAG pipeline | Search -> Context -> Generate | Core pattern for AI + private data |
| Similarity threshold | Filter out irrelevant results | Prevents hallucination from weak matches |
| "I don't know" | Admit when context is insufficient | Trust and reliability |
| Metadata filtering | Combine vector search + SQL WHERE | Target specific doc types, categories |
| Source citation | Track which doc the answer came from | Auditability and debugging |
