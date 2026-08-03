# Build 01: Embeddings Basics

Embeddings turn text into numbers that capture meaning. Similar texts get similar numbers. This is the foundation of RAG - without embeddings, you can't search by meaning.

---

## Step 1. Install the embedding model

We'll use `all-MiniLM-L6-v2` - a small, fast model that runs locally on your Mac. No API key needed. It produces 384-dimension vectors.

On your **Mac terminal**, run:

```bash
pip3 install sentence-transformers psycopg2-binary
```

Expected output (yours will differ):
```
Successfully installed sentence-transformers-5.5.1 torch-2.12.0 ...
```

---

## Step 2. Generate your first embedding

```bash
python3 << 'PYEOF'
from sentence_transformers import SentenceTransformer
import numpy as np
import time

start = time.time()
model = SentenceTransformer('all-MiniLM-L6-v2')
print(f"Model loaded in {time.time()-start:.1f}s")

text = "How to configure PostgreSQL streaming replication"
embedding = model.encode([text])[0]

print(f"Text: '{text}'")
print(f"Embedding shape: {embedding.shape}")
print(f"First 10 values: {embedding[:10].round(4)}")
print(f"Min: {embedding.min():.4f}, Max: {embedding.max():.4f}")
PYEOF
```

Expected output (yours will differ):
```
Model loaded in 1.2s
Text: 'How to configure PostgreSQL streaming replication'
Embedding shape: (384,)
First 10 values: [-0.0142  0.0381 -0.0082 ...]
Min: -0.1234, Max: 0.1567
```

- The model downloaded on first run (~90MB). After that it loads from cache.
- Each text becomes 384 numbers (floats between roughly -0.15 and 0.15)
- These 384 numbers capture the MEANING of the text

---

## Step 3. See similarity in action

The whole point: similar texts get similar embeddings. Let's prove it.

```bash
python3 << 'PYEOF'
from sentence_transformers import SentenceTransformer
import numpy as np

model = SentenceTransformer('all-MiniLM-L6-v2')

def cosine_similarity(a, b):
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))

texts = [
    "How to configure PostgreSQL streaming replication",
    "Setting up a read replica in PostgreSQL",
    "Making chocolate chip cookies at home",
    "PostgreSQL backup and recovery with pg_basebackup",
    "How to train a neural network from scratch",
]

embeddings = model.encode(texts)

query = model.encode(["How do I set up replication in PostgreSQL?"])[0]

print("Query: 'How do I set up replication in PostgreSQL?'")
print("-" * 60)

results = []
for i, text in enumerate(texts):
    sim = cosine_similarity(query, embeddings[i])
    results.append((sim, text))

results.sort(reverse=True)
for sim, text in results:
    bar = "#" * int(sim * 40)
    print(f"  {sim:.4f} {bar}")
    print(f"         {text}")
PYEOF
```

Expected output (yours will differ):
```
Query: 'How do I set up replication in PostgreSQL?'
------------------------------------------------------------
  0.7883 ###############################
         How to configure PostgreSQL streaming replication
  0.7332 #############################
         Setting up a read replica in PostgreSQL
  0.3288 #############
         PostgreSQL backup and recovery with pg_basebackup
  0.1741 ######
         Making chocolate chip cookies at home
  0.0781 ###
         How to train a neural network from scratch
```

The results make perfect sense:
- Replication config (0.79) and read replica setup (0.73) are the most similar - they're about the same topic
- Backup/recovery (0.33) is related but different
- Cookies (0.17) and neural networks (0.08) are completely unrelated

This is how RAG finds relevant documents. The embedding model understands meaning, not just keywords.

---

## Step 4. Embeddings understand meaning, not just keywords

This is the key insight that makes embeddings better than keyword search (LIKE, full-text search).

```bash
python3 << 'PYEOF'
from sentence_transformers import SentenceTransformer
import numpy as np

model = SentenceTransformer('all-MiniLM-L6-v2')

def cosine_similarity(a, b):
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))

# These docs DON'T contain the word "slow"
docs = [
    "High CPU usage indicates queries performing sequential scans on large tables",
    "Increase shared_buffers to cache more data pages in memory",
    "Missing indexes force PostgreSQL to scan entire tables",
    "Connection pooling with pgBouncer reduces connection overhead",
    "VACUUM ANALYZE updates table statistics for the query planner",
]

embeddings = model.encode(docs)

# Query uses "slow" - but no doc contains that word
query = model.encode(["Why are my database queries slow?"])[0]

print("Query: 'Why are my database queries slow?'")
print("(Note: NO document contains the word 'slow')")
print("-" * 60)

for i, doc in enumerate(docs):
    sim = cosine_similarity(query, embeddings[i])
    print(f"  {sim:.4f}  {doc[:70]}...")
PYEOF
```

Expected output (yours will differ):
```
Query: 'Why are my database queries slow?'
(Note: NO document contains the word 'slow')
------------------------------------------------------------
  0.5234  High CPU usage indicates queries performing sequential scans on larg...
  0.4891  Missing indexes force PostgreSQL to scan entire tables...
  0.4123  Increase shared_buffers to cache more data pages in memory...
  0.3876  VACUUM ANALYZE updates table statistics for the query planner...
  0.2145  Connection pooling with pgBouncer reduces connection overhead...
```

A keyword search for "slow" would return ZERO results. Embeddings found the right documents because they understand that "slow queries" relates to "sequential scans", "missing indexes", and "shared_buffers".

This is the superpower of RAG over traditional full-text search.

---

## Step 5. Batch embedding performance

In production, you embed hundreds or thousands of documents at once. Let's measure speed.

```bash
python3 << 'PYEOF'
from sentence_transformers import SentenceTransformer
import numpy as np
import time

model = SentenceTransformer('all-MiniLM-L6-v2')

# Generate 500 sample documents
docs = [f"PostgreSQL tip #{i}: some database advice about topic {i % 20}" for i in range(500)]

start = time.time()
embeddings = model.encode(docs, show_progress_bar=False, batch_size=64)
elapsed = time.time() - start

print(f"Documents: {len(docs)}")
print(f"Time: {elapsed:.2f}s")
print(f"Speed: {len(docs)/elapsed:.0f} docs/sec")
print(f"Embedding shape: {embeddings.shape}")
print(f"Memory: {embeddings.nbytes / 1024 / 1024:.1f} MB")
PYEOF
```

Expected output (yours will differ):
```
Documents: 500
Time: 0.85s
Speed: 588 docs/sec
Embedding shape: (500, 384)
Memory: 0.7 MB
```

- ~500 docs/sec on Apple Silicon - fast enough for most RAG systems
- 500 documents x 384 dimensions = only 0.7 MB of vectors
- Even 100K documents would only be ~150 MB of vectors
- The model runs locally - no API costs for embedding

---

## What You Learned

| Concept | What It Does | Why It Matters |
|---------|-------------|---------------|
| Embedding model | Turns text into 384-dim vectors | Enables semantic search |
| Cosine similarity | Measures how similar two vectors are | Ranks search results |
| Semantic search | Finds similar meaning, not just keywords | "slow queries" matches "missing indexes" |
| Batch encoding | Embeds many docs efficiently | Practical for production (500+ docs/sec) |
| Local model | Runs on your Mac, no API needed | Free, fast, private |
