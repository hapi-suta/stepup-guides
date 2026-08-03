# USE: Vector Distances and Cosine Similarity on Sentences

**Tier 2 - USE phase.** In BUILD you implemented cosine similarity on tiny hand-made vectors. Now you turn real sentences into vectors and measure which ones mean the same thing. You will build a bag-of-words embedding with nothing but NumPy - no heavy models, no downloads - so you can see exactly how "similarity" works before later tiers hand it to a neural network. This is the mechanical heart of semantic search and RAG.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25.

**Prerequisite:** you finished BUILD lab 2 (cosine similarity by hand) and read Concepts 2.2 (vectors, distance, cosine similarity, dimensionality).

**Goal:** given a query sentence, rank a small set of documents by semantic similarity and see that the ranking matches human intuition.

---

## Step 1: Set up the project

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/use-embeddings
```

Move into it:

```bash
cd ~/use-embeddings
```

Create and activate a virtual environment:

```bash
python3.12 -m venv .venv
```

```bash
source .venv/bin/activate
```

Install NumPy (the only dependency - the whole point is that this needs no heavy libraries):

```bash
pip install numpy
```

---

## Step 2: Understand the plan

A **bag-of-words embedding** turns a sentence into a vector by counting how often each word appears. Every position in the vector corresponds to one word in a shared vocabulary. Two sentences about the same topic share words, so their vectors point in a similar direction, so their cosine similarity is high. It ignores word order and meaning nuance (that is what real embeddings in later tiers fix), but it is enough to see the machinery clearly.

Steps in the script:

1. Build a vocabulary from all sentences.
2. Turn each sentence into a word-count vector (its embedding).
3. Compare a query against every document with cosine similarity and Euclidean distance.
4. Rank the documents.

---

## Step 3: Write the embedding and search script

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi embed_search.py
```

Press `i` and enter:

```python
import numpy as np
import re

# Our little document collection.
documents = [
    "The database server crashed and lost all connections",
    "PostgreSQL replication fell behind on the standby node",
    "The cat sat quietly on the warm windowsill",
    "Our backup job failed so the database was not protected",
    "She baked fresh bread for the neighborhood bake sale",
]

query = "the database went down and we lost data"

def tokenize(text):
    """Lowercase and split into words, dropping punctuation."""
    return re.findall(r"[a-z]+", text.lower())

# --- Step 1: build the shared vocabulary from every sentence ---
all_text = documents + [query]
vocab = sorted(set(word for sentence in all_text for word in tokenize(sentence)))
vocab_index = {word: i for i, word in enumerate(vocab)}
print(f"Vocabulary size (dimensions): {len(vocab)}")

def embed(text):
    """Turn a sentence into a word-count vector over the vocabulary."""
    vec = np.zeros(len(vocab))
    for word in tokenize(text):
        vec[vocab_index[word]] += 1
    return vec

def cosine_similarity(a, b):
    denom = np.linalg.norm(a) * np.linalg.norm(b)
    return 0.0 if denom == 0 else np.dot(a, b) / denom

def euclidean_distance(a, b):
    return np.linalg.norm(a - b)

# --- Step 2 and 3: embed the query, compare against each document ---
q_vec = embed(query)
results = []
for doc in documents:
    d_vec = embed(doc)
    results.append((
        cosine_similarity(q_vec, d_vec),
        euclidean_distance(q_vec, d_vec),
        doc,
    ))

# --- Step 4: rank by cosine similarity, highest first ---
results.sort(key=lambda r: r[0], reverse=True)

print(f"\nQuery: {query!r}\n")
print(f"{'cosine':>7}  {'distance':>8}  document")
print("-" * 70)
for cos, dist, doc in results:
    print(f"{cos:7.3f}  {dist:8.3f}  {doc}")

best = results[0]
print(f"\nBest match: {best[2]!r}")
print(f"(cosine {best[0]:.3f})")
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 4: Run the search

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python embed_search.py
```

Expected output (yours will differ slightly in the numbers):

```
Vocabulary size (dimensions): 40

Query: 'the database went down and we lost data'

 cosine  distance  document
----------------------------------------------------------------------
  0.500     2.828  The database server crashed and lost all connections
  0.224     3.742  The cat sat quietly on the warm windowsill
  0.224     3.742  Our backup job failed so the database was not protected
  0.125     3.742  PostgreSQL replication fell behind on the standby node
  0.118     3.873  She baked fresh bread for the neighborhood bake sale

Best match: 'The database server crashed and lost all connections'
```

Read the results. The best match by far is the sentence about the database crashing and losing connections - it shares the words "database", "lost", and "the" with the query, so its cosine of 0.500 towers over the rest. The machine, with no idea what a database is, still surfaced the on-topic sentence first. That is retrieval.

Now look closer, because the flaws are the lesson. The cat sentence tied the backup sentence at 0.224 - purely because both share the common word "the" with the query, which carries no meaning. Raw word counts let filler words like "the" pollute the ranking. Real systems remove such **stop words** and weight rare, informative words more heavily (a technique called TF-IDF). Notice also that cosine (direction) and Euclidean distance (magnitude) disagree on exact ordering here. For text search, cosine is the standard because sentence length should not drown out topic - a point straight from Concepts 2.2.

---

## Step 5: Explore - watch synonyms break bag-of-words

Bag-of-words only matches exact words. Prove its limit. Open the script:

```bash
vi embed_search.py
```

Press `i` and change the query line to use synonyms instead of shared words:

```python
query = "the db outage destroyed our records"
```

Press `Esc`, type `:wq`, press Enter. Run again:

```bash
python embed_search.py
```

Expected output (yours will differ):

```
...
Best match: 'The cat sat quietly on the warm windowsill'
(cosine 0.258)
```

Something has gone badly wrong, and that is the whole point. The top match is now the sentence about a cat on a windowsill, which has nothing to do with a database outage. The scores collapsed because "db" is not "database", "outage" is not "crashed", and "records" is not "data" - so the only overlap left is filler words like "the" and "our", and the cat sentence happens to share those. A human sees the query and the database sentences as obviously the same topic, but bag-of-words does not, because it has no concept of meaning, only exact words. This is precisely the gap that trained neural embeddings close in later tiers: they place synonyms near each other in vector space even when the words differ. You just felt, firsthand, why we need them.

Restore the original query when done:

```bash
vi embed_search.py
```

Set `query = "the database went down and we lost data"` again, save with `:wq`.

---

## What you practiced

- Turned real sentences into vectors (embeddings) with a bag-of-words model, in pure NumPy.
- Ranked documents against a query using cosine similarity and Euclidean distance - the exact mechanic of semantic search and RAG.
- Saw why cosine (direction) is preferred over raw distance for text.
- Discovered the limitation of word-count embeddings (no synonyms, no meaning), motivating the trained embeddings you will use in later tiers.

You have now applied every pillar of this tier - statistics in the A/B test, linear algebra here - to fresh problems. Next: the SURVIVE scenarios, where things go wrong and you have to diagnose them.
