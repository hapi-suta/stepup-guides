# Concepts: Math for AI

## Why Math?

You don't need a math degree to use AI. But you need enough math to understand what's happening inside the models you build. Without it, AI is a black box - you're just copying code and hoping it works.

Think of it like being a DBA. You don't need to write the PostgreSQL source code, but you DO need to understand:
- How indexes work (B-trees, hash)
- What EXPLAIN output means
- Why VACUUM matters

Same idea with AI math. You don't need to derive formulas. You need to understand what the numbers mean and why they matter.

## What Math Does AI Actually Use?

Four areas. That's it.

### 1. Vectors - "A Row of Numbers"

You already know what a vector is. You've seen them.

```sql
-- This query result is a vector (a list of numbers):
SELECT temperature, humidity, wind_speed FROM weather WHERE city = 'NYC';
-- Result: [72.5, 65.0, 12.3]
```

That's a vector: `[72.5, 65.0, 12.3]`. Three numbers in a row.

In Module 03 (RAG), you stored embeddings in pgvector. Those embeddings were vectors - lists of 384 numbers that represent the MEANING of text.

```sql
-- This is a 384-dimensional vector stored in your database:
SELECT embedding FROM documents WHERE source = 'backup-guide';
-- Result: [0.023, -0.156, 0.089, ..., 0.041]  (384 numbers)
```

**Why it matters:** Every piece of data in AI - text, images, audio - gets converted to vectors. If you don't understand vectors, you can't understand AI.

### 2. Matrices - "A Table of Numbers"

A matrix is just a table. You think in tables every day.

```
-- pg_stat_activity is a matrix:
  pid  | cpu  | memory | duration
-------+------+--------+---------
  1234 | 45.2 |  128   |   30
  1235 | 12.8 |   64   |    5
  1236 | 92.1 |  256   |  120
```

That's a 3x4 matrix (3 rows, 4 columns). Neural networks are basically chains of matrix operations - multiply one table of numbers by another to get predictions.

**Why it matters:** When you hear "the model has 7 billion parameters," those parameters are stored in matrices. Training = adjusting the numbers in those matrices.

### 3. Statistics - "Measuring Your Data"

You already use statistics as a DBA:

```sql
-- You run this kind of thing all the time:
SELECT
    avg(query_time) AS average,      -- mean
    percentile_cont(0.5) WITHIN GROUP (ORDER BY query_time) AS median,
    stddev(query_time) AS spread,    -- standard deviation
    count(*) AS total
FROM pg_stat_statements;
```

AI uses the same concepts:
- **Mean** = average model error (is the model getting better?)
- **Standard deviation** = how spread out the data is (is the data consistent?)
- **Distribution** = what does the data look like? (is it skewed? normal?)
- **Correlation** = do two things move together? (feature selection)

**Why it matters:** You can't evaluate a model without statistics. "93% accuracy" means nothing if you don't understand what that number hides.

### 4. Calculus Intuition - "Which Way Is Downhill?"

This is the one that scares people. But you don't need to DO calculus. You need ONE concept:

**Gradient = the direction that makes the model less wrong.**

Imagine you're tuning `shared_buffers`. You try different values and measure query speed:

```
shared_buffers = 128MB  -> avg query: 50ms
shared_buffers = 256MB  -> avg query: 35ms  (better!)
shared_buffers = 512MB  -> avg query: 20ms  (better!)
shared_buffers = 1024MB -> avg query: 22ms  (worse - went too far)
```

You went in one direction (increase memory), measured the result, and adjusted. That's exactly what gradient descent does:
1. Try some values (weights)
2. Measure how wrong the model is (loss)
3. Adjust in the direction that reduces the error (gradient)
4. Repeat

**Why it matters:** Every model training loop uses gradient descent. You don't need to code it (PyTorch does it for you), but you need to understand what "the loss is not decreasing" means and what to do about it.

## What You DON'T Need

- Proofs or derivations (leave that to researchers)
- Linear algebra beyond matrix multiply (no eigenvalues, no SVD)
- Calculus beyond the gradient concept (no integrals, no chain rule by hand)
- Probability theory beyond basics (no Bayesian inference, no Markov chains)

## The DBA Analogy

| Math Concept | DBA Equivalent | AI Use |
|-------------|---------------|--------|
| Vector | A row from a query result | Embeddings, features, model inputs |
| Matrix | A table (rows and columns) | Model weights, batch processing |
| Dot product | Similarity score between two rows | How similar are two embeddings? |
| Mean / std dev | `avg()` and `stddev()` in SQL | Model evaluation, data analysis |
| Gradient | "Tune this parameter up or down?" | Training - adjusting model weights |
| Loss function | Error rate in monitoring | "How wrong is the model right now?" |
| Learning rate | Step size when tuning | "How much do we adjust each time?" |

## What You'll Build

| Build | Topic | What You'll Understand |
|-------|-------|----------------------|
| 01 | Vectors | What embeddings actually are |
| 02 | Matrices | What happens inside a neural network layer |
| 03 | Statistics | How to evaluate if your model is working |
| 04 | Calculus Intuition | How models learn (gradient descent) |
