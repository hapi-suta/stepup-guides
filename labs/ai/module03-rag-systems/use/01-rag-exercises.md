# USE: RAG Systems Exercises

These exercises build on the pgvector + Claude RAG pipeline from the BUILD guides. Each one adds a real-world capability.

---

## Exercise 1: Load Your Own Documentation

**Task:** Take a real markdown file from your SUTA Labs content (or any PostgreSQL documentation you have) and build a RAG system over it.

1. Read the file
2. Split it into chunks using section-based chunking
3. Embed and store the chunks in pgvector
4. Query it with 5 relevant questions
5. Print the answer with source citations

Use a file of at least 500 words. If you don't have one handy, use the PostgreSQL docs for any feature you know well and create a markdown file.

<details>
<summary>Hint</summary>

```python
import re

def chunk_by_headers(text):
    """Split markdown on ## headers, keeping the header with its content."""
    sections = re.split(r'\n(?=## )', text)
    return [s.strip() for s in sections if len(s.strip()) > 50]

# Read the file
with open('path/to/your/guide.md', 'r') as f:
    content = f.read()

chunks = chunk_by_headers(content)
# Then embed and store each chunk...
```
</details>

---

## Exercise 2: Hybrid Search (Vector + Full-Text)

**Task:** Sometimes pure semantic search misses exact matches. Build a hybrid search that combines pgvector similarity with PostgreSQL full-text search (`tsvector`).

1. Add a `tsv` column to the documents table: `ALTER TABLE documents ADD COLUMN tsv tsvector;`
2. Populate it: `UPDATE documents SET tsv = to_tsvector('english', content);`
3. Create a GIN index on it
4. Write a search function that:
   - Runs vector similarity search (top 10)
   - Runs full-text search (top 10)
   - Combines scores: `final_score = 0.7 * vector_sim + 0.3 * text_rank`
   - Returns top 5 by combined score

Test with: "pg_stat_replication replay_lag" - full-text should boost the monitoring guide because it contains those exact terms.

<details>
<summary>Hint</summary>

```sql
-- Full-text search with ranking
SELECT content, source, ts_rank(tsv, plainto_tsquery('english', 'pg_stat_replication replay_lag')) AS text_rank
FROM documents
WHERE tsv @@ plainto_tsquery('english', 'pg_stat_replication replay_lag');

-- Combine in Python:
-- Run both queries, merge results by source, compute weighted score
```
</details>

---

## Exercise 3: Conversational RAG

**Task:** Build a RAG chatbot that maintains conversation history. Each turn should:

1. Search pgvector using the LATEST question (not the whole conversation)
2. Include the last 3 turns of conversation in the Claude prompt for context
3. Include retrieved documents as context
4. Return the answer

Test conversation:
- Turn 1: "How does replication work?"
- Turn 2: "How do I check if it's healthy?" (should understand "it" = replication)
- Turn 3: "What if the lag is over 60 seconds?" (should understand context)

The tricky part: the embedding search should use the original question, but Claude should see the full conversation for context.

<details>
<summary>Hint</summary>

```python
conversation = []

def conversational_rag(question, conversation):
    # Search uses only the current question
    docs = search(question)

    # But Claude sees the full conversation
    messages = []
    for turn in conversation[-3:]:  # Last 3 turns
        messages.append({"role": "user", "content": turn["user"]})
        messages.append({"role": "assistant", "content": turn["assistant"]})
    messages.append({"role": "user", "content": f"Context:\n{context}\n\nQuestion: {question}"})
    # ...
```
</details>

---

## Exercise 4: Document Ingestion Pipeline

**Task:** Build an automated pipeline that:

1. Watches a directory for new `.md` files
2. When a new file appears, automatically:
   - Reads it
   - Chunks it by headers
   - Generates embeddings
   - Stores in pgvector with metadata (filename, timestamp, word count)
3. Prints a summary of what was ingested

```python
# Skeleton:
import os
import time

watch_dir = "/tmp/rag-docs/"
os.makedirs(watch_dir, exist_ok=True)
processed = set()

while True:
    files = set(f for f in os.listdir(watch_dir) if f.endswith('.md'))
    new_files = files - processed
    for f in new_files:
        # Read, chunk, embed, store
        pass
    processed.update(new_files)
    time.sleep(5)
```

Test by dropping 3 markdown files into the watch directory and verifying they appear in pgvector.

<details>
<summary>Hint</summary>

- Use `os.path.getmtime()` for file timestamp
- Use `len(content.split())` for word count
- Store metadata as JSONB: `{"filename": "guide.md", "ingested_at": "2026-06-09", "words": 450}`
- After ingestion, query the documents table to verify
</details>

---

## Exercise 5: RAG Evaluation

**Task:** Build a test suite that measures your RAG system's quality. Create 10 question-answer pairs where you KNOW the correct answer, then measure:

1. **Retrieval accuracy:** Did the top-3 results include the right source document?
2. **Answer relevance:** Does the generated answer actually address the question?
3. **Faithfulness:** Does the answer only use information from the retrieved context?

```python
# Test cases: question, expected_source, expected_keywords
test_cases = [
    ("How do I check replication lag?", "pg-monitoring-guide", ["pg_stat_replication", "replay_lag"]),
    ("How do I reduce table bloat?", "pg-vacuum-guide", ["VACUUM", "dead tuples"]),
    ("How to create an index without locking?", "pg-indexing-guide", ["CONCURRENTLY"]),
    # Add 7 more...
]

# For each test case:
# 1. Run RAG query
# 2. Check if expected_source is in top 3 results
# 3. Check if expected_keywords appear in the answer
# 4. Score: retrieval_hits / total, keyword_hits / total
```

This is how you know if your RAG system actually works before putting it in production. Without evaluation, you're guessing.

<details>
<summary>Hint</summary>

- A good RAG system should hit 80%+ on retrieval accuracy
- If retrieval is bad, the problem is usually chunking or embedding quality
- If retrieval is good but answers are bad, the problem is the generation prompt
- Track scores over time as you add documents or change chunking
</details>
