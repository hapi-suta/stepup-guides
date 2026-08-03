# SURVIVE 02: The Chunk Size Disaster

## Scenario

You loaded your company's entire PostgreSQL operations manual (50 pages) into the RAG system. Queries that used to work great now return garbage. Users ask "How do I check replication?" and get a paragraph about backup configuration mixed with monitoring commands and upgrade instructions.

The problem: you chunked the 50-page document with a fixed 2000-word chunk size. Each chunk contains multiple unrelated topics mashed together. The embeddings are diluted - they don't represent any single topic well.

---

## The Broken System

```bash
cat > /tmp/survive_chunks.py << 'PYEOF'
import psycopg2
from sentence_transformers import SentenceTransformer
import numpy as np

conn = psycopg2.connect("dbname=postgres host=/tmp")
conn.autocommit = True
cur = conn.cursor()
model = SentenceTransformer('all-MiniLM-L6-v2')

# Simulate a big document with multiple topics per chunk (BAD chunking)
big_doc = """
Section: Replication Setup
PostgreSQL streaming replication copies WAL records from a primary to standbys.
Set wal_level=replica and max_wal_senders=10 in postgresql.conf.
Use pg_basebackup to initialize standbys.

Section: Backup Configuration
Configure archive_mode=on for WAL archiving. Set archive_command to copy
WAL files to S3. Run pg_basebackup daily at 2am via cron.

Section: Monitoring
Use pg_stat_replication to check lag. Monitor pg_stat_activity for
long-running queries. Set up alerting when connections exceed 80%.

Section: Performance Tuning
Set shared_buffers to 25% of RAM. Configure work_mem based on
max_connections. Use pg_stat_statements to find slow queries.

Section: Security
Use ssl=on for encrypted connections. Configure pg_hba.conf with
scram-sha-256. Rotate passwords quarterly. Audit with pgAudit.

Section: Upgrades
Use pg_upgrade for major version upgrades. Always test on staging first.
Back up before upgrading. Check extension compatibility.
"""

# BAD: One giant chunk (entire document)
giant_chunk = big_doc.strip()
giant_emb = model.encode([giant_chunk])[0]

# GOOD: Individual section chunks
import re
sections = [s.strip() for s in re.split(r'\nSection: ', big_doc) if s.strip()]
section_embs = model.encode(sections)

# Test queries
queries = [
    "How do I set up replication?",
    "How do I configure backups?",
    "How do I monitor the database?",
    "How do I tune performance?",
    "How do I secure the database?",
]

def cosine_sim(a, b):
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))

print("=== ONE GIANT CHUNK (all similarity scores are similar - BAD) ===")
for q in queries:
    q_emb = model.encode([q])[0]
    sim = cosine_sim(q_emb, giant_emb)
    print(f"  {sim:.4f}  {q}")

print()
print("=== INDIVIDUAL SECTIONS (clear winners - GOOD) ===")
for q in queries:
    q_emb = model.encode([q])[0]
    sims = [(cosine_sim(q_emb, section_embs[i]), sections[i][:50]) for i in range(len(sections))]
    sims.sort(reverse=True)
    best_sim, best_section = sims[0]
    second_sim = sims[1][0]
    gap = best_sim - second_sim
    print(f"  {best_sim:.4f} (gap: {gap:.4f})  {q}")
    print(f"    -> {best_section}...")

print()
print("=== DIAGNOSIS ===")
# Show that the giant chunk has similar scores for all queries (no discrimination)
q_embs = model.encode(queries)
giant_sims = [cosine_sim(q, giant_emb) for q in q_embs]
section_best_sims = []
for q_emb in q_embs:
    sims = [cosine_sim(q_emb, s) for s in section_embs]
    section_best_sims.append(max(sims))

print(f"Giant chunk sim range:    {min(giant_sims):.4f} - {max(giant_sims):.4f} (spread: {max(giant_sims)-min(giant_sims):.4f})")
print(f"Section chunk best range: {min(section_best_sims):.4f} - {max(section_best_sims):.4f} (spread: {max(section_best_sims)-min(section_best_sims):.4f})")
print()
print(f"Giant chunk: all queries score ~{np.mean(giant_sims):.2f} (can't tell them apart)")
print(f"Section chunks: best match is clearly different from second best")

conn.close()
PYEOF
python3 /tmp/survive_chunks.py
```

Expected behavior:
- Giant chunk: all queries get similar similarity scores (~0.35-0.40) because the embedding represents EVERYTHING and NOTHING specifically
- Section chunks: each query clearly matches its correct section with a visible gap to the second-best

---

## Your Mission

1. **Run the diagnostic** and observe the difference in similarity scores
2. **Experiment with chunk sizes:** Try splitting the document into 2 chunks, 3 chunks, 6 chunks (one per section), and 12 chunks (splitting each section in half)
3. **Find the sweet spot** where retrieval accuracy is highest
4. **Write a chunking function** that handles a real-world document with these characteristics:
   - Has `##` headers that mark topic boundaries
   - Some sections are 20 words (too small alone)
   - Some sections are 500 words (fine as-is)
   - Needs to handle code blocks (don't split inside a code block)

**Rules:**
- Minimum chunk size: 30 words (smaller chunks lose context)
- Maximum chunk size: 300 words (larger chunks dilute the embedding)
- Small sections should be merged with adjacent sections
- Code blocks should never be split

---

## Validation

Your chunking function should pass these tests:

```python
# Test 1: Doesn't split code blocks
text_with_code = "## Config\nSet these values:\n```\nshared_buffers = 4GB\nwork_mem = 256MB\neffective_cache_size = 12GB\n```\nRestart PostgreSQL after changes."
chunks = your_chunk_function(text_with_code)
assert all("```" not in c or c.count("```") % 2 == 0 for c in chunks), "Split inside code block!"

# Test 2: Small sections merged
text_small = "## A\nTiny section.\n## B\nAlso tiny.\n## C\nThis one has enough content to stand alone and contains multiple sentences about configuration and setup and deployment."
chunks = your_chunk_function(text_small)
assert len(chunks) <= 2, f"Should merge tiny sections, got {len(chunks)} chunks"

# Test 3: Large sections respected
text_large = "## Big Section\n" + "This is a sentence about databases. " * 100
chunks = your_chunk_function(text_large)
assert all(len(c.split()) <= 300 for c in chunks), "Chunk exceeds 300 words!"
```

<details>
<summary>Runbook (hints, not answers)</summary>

1. **The core insight:** Embeddings work best when each chunk is about ONE topic. When you mash 6 topics into one chunk, the embedding becomes a blurry average of all topics.

2. **Measure the "discrimination gap"**: For a good chunk, the best-match similarity should be noticeably higher than the second-best. If they're close, the chunk is too generic.

3. **Handling code blocks:** Use regex to find ``` pairs and treat everything between them as atomic (never split).

4. **Merging small sections:** Iterate through chunks. If a chunk is under 30 words, append it to the previous chunk (or the next one if it's the first).

5. **The practical answer for most DBA documentation:** Split on `##` headers. Merge sections under 30 words with their neighbor. If a section exceeds 300 words, split on paragraph boundaries (`\n\n`). This handles 90% of real runbooks.
</details>
