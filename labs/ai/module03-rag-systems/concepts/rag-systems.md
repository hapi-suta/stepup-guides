# Concepts: RAG Systems

## What Is RAG?

RAG stands for Retrieval-Augmented Generation. It's a way to give an AI model access to YOUR data before it answers a question.

Without RAG, Claude only knows what it learned during training. It doesn't know your database schemas, your runbooks, your monitoring setup, or your company's naming conventions. Ask it "what's the replication status on pg-primary?" and it'll give a generic answer about replication - not YOUR replication.

With RAG, you:
1. Store your documents (runbooks, configs, logs) in a database
2. When a user asks a question, find the most relevant documents
3. Feed those documents to Claude along with the question
4. Claude answers using YOUR data, not just its training

## DBA Analogy

You already do RAG manually. When a junior DBA asks you "how do I fix replication lag?", you don't answer from memory alone. You pull up the runbook, check the monitoring dashboard, look at recent incident reports, then give an answer that's specific to YOUR environment.

RAG automates that process:
- The runbook, dashboard data, and incident reports = your **document store**
- "Pull up the relevant ones" = **retrieval** (similarity search)
- "Give an answer specific to your environment" = **generation** (Claude with context)

## How It Works (5 Steps)

```
USER ASKS: "Why is replication lagging on pg-primary?"

Step 1. EMBED the question
   Turn the question into numbers (a vector)
   [0.82, 0.15, 0.41, ...] (384 dimensions)

Step 2. SEARCH the vector database
   Find documents with similar vectors
   -> "Replication monitoring guide" (similarity: 0.84)
   -> "Replication troubleshooting runbook" (similarity: 0.71)
   -> "pg-primary configuration" (similarity: 0.65)

Step 3. BUILD the prompt
   System: "You are a DBA assistant. Use ONLY the context below."
   Context: [the 3 retrieved documents]
   User: "Why is replication lagging on pg-primary?"

Step 4. GENERATE the answer
   Claude reads the context + question and responds with
   specific advice from YOUR documentation

Step 5. RETURN to user
   A grounded answer that references your actual setup
```

## Why pgvector?

You already run PostgreSQL. pgvector adds vector storage and similarity search to the database you know. No new infrastructure.

| Option | What It Is | Tradeoff |
|--------|-----------|----------|
| **pgvector** | PostgreSQL extension | You already know PostgreSQL. Same backup, same monitoring, same SQL. Limited to ~5M vectors before needing optimization. |
| Pinecone | Managed vector DB | Zero ops, scales to billions of vectors. Costs money, another service to manage. |
| Weaviate | Open source vector DB | Feature-rich, supports hybrid search. Another database to learn and operate. |
| ChromaDB | Lightweight, Python-native | Easy to start, runs in-process. Not production-grade for large datasets. |

For learning and for moderate-scale production (under 5M documents), pgvector is the right choice. You don't need another database.

## Key Concepts

### Embeddings
Numbers that capture the MEANING of text. Similar texts get similar numbers. "PostgreSQL replication" and "streaming replica setup" have similar embeddings. "PostgreSQL replication" and "chocolate cake recipe" do not.

The model we'll use (all-MiniLM-L6-v2) produces 384-dimension vectors. Each document becomes a list of 384 numbers.

### Chunking
Documents are too long to embed as one piece. You split them into chunks. Chunk size matters:
- **Too small** (1 sentence): loses context, retrieval finds fragments
- **Too large** (entire chapter): embedding is too diluted, search is imprecise
- **Just right** (1-3 paragraphs): captures a complete thought, searchable

### Similarity Search
Find the chunks most similar to the query. pgvector uses **cosine distance** - it measures the angle between two vectors. Smaller angle = more similar.

The SQL operator `<=>` calculates cosine distance:
```sql
SELECT content, 1 - (embedding <=> query_vector) AS similarity
FROM documents
ORDER BY embedding <=> query_vector
LIMIT 5;
```

### HNSW Index
Without an index, similarity search scans every row (like a sequential scan). HNSW (Hierarchical Navigable Small World) is an approximate nearest neighbor index - like a B-tree for vectors. It makes search fast at the cost of occasionally missing the absolute best match.

```sql
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
```

## RAG vs Fine-Tuning

| | RAG | Fine-Tuning |
|---|-----|------------|
| **What it does** | Gives the model a cheat sheet during the test | Teaches the model the material beforehand |
| **Data needed** | Any documents (PDFs, markdown, logs) | Structured input/output pairs (thousands) |
| **Update speed** | Instant - add/remove documents anytime | Hours/days - retrain the model |
| **Cost** | Embedding + storage + per-query retrieval | Training cost (GPU hours) + per-query inference |
| **Best for** | Company docs, runbooks, knowledge that changes | Consistent style, specialized reasoning, custom formats |
| **Start here** | Yes - always try RAG first | Only when RAG isn't enough |

## What You'll Build

In this module you'll build a working RAG system that:
1. Takes your PostgreSQL runbooks and documentation
2. Chunks and embeds them
3. Stores them in pgvector
4. Answers questions using your actual documentation
5. Cites which document it used

## Prerequisites

- PostgreSQL 17 running locally with pgvector extension
- Python with sentence-transformers and psycopg2
- Anthropic API key (for the generation step)
