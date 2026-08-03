# Concepts: Python for AI

## What Is This Module?

You already know Python. You write bash scripts, you use SQL daily, you've built tools with it. This module is NOT "learn Python from scratch." It's about three libraries that every AI engineer uses daily:

- **NumPy** - fast math on arrays of numbers
- **Pandas** - SQL-like data manipulation in Python
- **Matplotlib** - charts and visualizations (think: Grafana but in code)

## Why These Three?

Every AI system runs on data. Before you can train a model, build a RAG pipeline, or evaluate results, you need to:

1. **Load data** (Pandas reads CSV, JSON, SQL, Excel)
2. **Clean data** (handle missing values, filter, transform)
3. **Do math on data** (NumPy handles vectors, matrices, statistics)
4. **Visualize data** (Matplotlib shows patterns your eyes can catch)

This is the same workflow you already do as a DBA - you just do it in psql and Grafana. Now you'll do it in Python.

## How It Connects to AI

| AI Concept | Python Tool | DBA Equivalent |
|-----------|-------------|----------------|
| Embeddings (vectors of numbers) | NumPy arrays | Numeric column values |
| Training data preparation | Pandas DataFrames | SQL result sets |
| Model evaluation metrics | NumPy math (mean, std) | pg_stat_statements averages |
| Loss curves, accuracy plots | Matplotlib charts | Grafana dashboards |
| Similarity search | NumPy dot product | Index lookups |

## Key Concept: Everything Is Numbers

AI models don't understand words, images, or database schemas. They understand numbers - specifically, arrays of numbers (called **tensors**).

- A word becomes a list of 1,536 numbers (an **embedding**)
- An image becomes a grid of numbers (pixel values)
- A sentence becomes a sequence of number-lists

NumPy is how you work with these numbers fast. Pandas is how you organize and clean the data before it becomes numbers. Matplotlib is how you look at the numbers to see if something went wrong.

## Key Concept: Vectorized Operations

In SQL, you write `SELECT AVG(duration_ms) FROM queries` and the database handles looping over rows internally.

NumPy works the same way. Instead of writing a Python for-loop over 1 million numbers, you write `array.mean()` and NumPy handles it in optimized C code. This is called **vectorization** - it's 100x faster than Python loops.

This matters in AI because you're constantly doing math on millions of numbers.

## Key Concept: DataFrames Are Result Sets

A Pandas DataFrame is essentially a SQL result set you can keep manipulating. If you can write SQL, you can use Pandas:

| SQL | Pandas |
|-----|--------|
| `SELECT * FROM table` | `df` |
| `SELECT col1, col2 FROM table` | `df[['col1', 'col2']]` |
| `WHERE duration > 100` | `df[df['duration'] > 100]` |
| `GROUP BY database` | `df.groupby('database')` |
| `ORDER BY duration DESC` | `df.sort_values('duration', ascending=False)` |
| `COUNT(*)` | `len(df)` or `df.shape[0]` |
| `AVG(duration)` | `df['duration'].mean()` |
| `IS NULL` | `df['col'].isna()` |

## What You'll Build

In this module you'll analyze a realistic database query log - the same kind of data you work with daily. By the end, you'll be comfortable loading, cleaning, analyzing, and visualizing data in Python.

## Prerequisites

- Python basics (variables, functions, loops, dictionaries)
- Anaconda or pip with NumPy, Pandas, Matplotlib installed
- A terminal (you'll run Python scripts directly - no Jupyter required for this module)
