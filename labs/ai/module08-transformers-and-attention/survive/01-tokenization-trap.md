# SURVIVE 01: The Tokenization Trap

Your RAG system returns wrong results for database queries. The embeddings look fine, the vector search works, but the model keeps matching the wrong documents. The problem is tokenization.

---

## The Scenario

A DBA built a RAG system to search PostgreSQL documentation. When they search for "pg_stat_replication", the system returns results about "statistics" and "replication" separately - not the specific `pg_stat_replication` view. Technical terms get split into subwords, losing their meaning.

---

## Step 1. See the problem

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("gpt2")

# Database terms that get split badly
technical_terms = [
    "pg_stat_replication",
    "pg_stat_user_tables",
    "wal_level",
    "max_wal_senders",
    "shared_buffers",
    "postgresql.conf",
    "pg_basebackup",
    "autovacuum_max_workers",
]

print("How tokenizers DESTROY database terminology:")
print("=" * 65)
print(f"{'Term':30s}  {'Tokens':>3s}  Subwords")
print("-" * 65)

for term in technical_terms:
    tokens = tokenizer.encode(term)
    subwords = [tokenizer.decode([t]) for t in tokens]
    # Show how the term gets split
    print(f"{term:30s}  {len(tokens):>3d}  {subwords}")

print()
print("PROBLEM: 'pg_stat_replication' becomes ['pg', '_stat', '_repl', 'ication']")
print("The model sees 4 separate pieces, not one concept")
print("Searches for 'pg_stat_replication' match documents about 'statistics'")
print("or 'replication' separately - not the specific PostgreSQL view")
PYEOF
```

Expected output (yours will differ):

```
How tokenizers DESTROY database terminology:
=================================================================
Term                            Tokens  Subwords
-----------------------------------------------------------------
pg_stat_replication                  4  ['pg', '_stat', '_repl', 'ication']
pg_stat_user_tables                  5  ['pg', '_stat', '_user', '_tables', '']
wal_level                            3  ['wal', '_level', '']
...

PROBLEM: 'pg_stat_replication' becomes ['pg', '_stat', '_repl', 'ication']
```

---

## Step 2. See how this breaks search

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
from transformers import AutoTokenizer, AutoModel
import numpy as np
from numpy.linalg import norm

tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")
model = AutoModel.from_pretrained("bert-base-uncased")
model.eval()

def get_embedding(text):
    inputs = tokenizer(text, return_tensors="pt", padding=True, truncation=True)
    with torch.no_grad():
        outputs = model(**inputs)
    return outputs.last_hidden_state.mean(dim=1).squeeze().numpy()

def cosine_sim(a, b):
    return np.dot(a, b) / (norm(a) * norm(b))

# Documentation chunks (simulating a RAG knowledge base)
docs = [
    "pg_stat_replication shows the status of WAL sender processes connected to standby servers",
    "pg_stat_user_tables shows per-table statistics including sequential scans and index scans",
    "The replication lag indicates how far behind a standby server is from the primary",
    "PostgreSQL statistics collector tracks table and index usage patterns",
    "Configure max_wal_senders in postgresql.conf to allow standby connections",
]

doc_embeddings = [get_embedding(d) for d in docs]

# Search queries
queries = [
    "pg_stat_replication",
    "How do I check replication status?",
]

print("RAG Search Results:")
print("=" * 70)

for query in queries:
    query_emb = get_embedding(query)
    scores = [(cosine_sim(query_emb, de), i) for i, de in enumerate(doc_embeddings)]
    # List comprehension creates (score, index) pairs for all docs
    scores.sort(reverse=True)  # sort by score, highest first

    print(f"\nQuery: '{query}'")
    for score, idx in scores[:3]:
        print(f"  {score:.3f}  {docs[idx][:65]}...")

print()
print("PROBLEM: Searching 'pg_stat_replication' might rank general")
print("replication or statistics docs higher than the specific view doc")
print("because the tokenizer splits it into generic subwords")
PYEOF
```

---

## Step 3. The fixes

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Tokenization Trap - Three Fixes:

FIX 1: Add context to your search queries
  BAD:  "pg_stat_replication"
  GOOD: "pg_stat_replication PostgreSQL view that shows standby replication status"

  By adding human-readable description, you give the model more
  tokens that capture the actual meaning.

FIX 2: Use a domain-specific embedding model
  General models (BERT, GPT-2) weren't trained on PostgreSQL terminology.
  Models fine-tuned on code/technical docs handle this better:
    - microsoft/codebert-base (trained on code)
    - sentence-transformers/all-MiniLM-L6-v2 (good for similarity)

  The sentence-transformers models are specifically trained for
  semantic similarity - they produce better embeddings for search.

FIX 3: Hybrid search (embedding + keyword)
  Combine vector similarity (catches meaning) with keyword matching
  (catches exact technical terms):

  score = 0.7 * cosine_similarity + 0.3 * keyword_match_score

  This way, "pg_stat_replication" gets a boost when the document
  contains that exact string, even if the embedding is noisy.

FIX 4: Chunk your documents better
  BAD:  One chunk per page (might mix unrelated topics)
  GOOD: One chunk per concept/section (keeps meaning focused)

  If a chunk talks about BOTH replication AND statistics,
  it will match queries about either one equally well.
  Split it into two chunks so each is specific.

MOST IMPORTANT LESSON:
  Tokenization is invisible but affects everything downstream.
  If your RAG or classification system gives wrong results,
  check tokenization FIRST - it's often the root cause.
""")
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Technical terms split into subwords | Search returns wrong results | Add context to queries |
| General model for domain-specific text | Poor embedding quality | Use domain-specific models |
| Pure vector search | Misses exact term matches | Hybrid search (vector + keyword) |
| Large document chunks | Matches too broadly | Smaller, focused chunks |
