# Build 01: NumPy Fundamentals

NumPy is the math engine behind all of AI. Every model, every embedding, every calculation runs through NumPy arrays. This guide teaches you the operations you'll use constantly.

## Python Foundations Reference

If you're coming from SQL and haven't used Python before, here are the patterns you'll see throughout this entire curriculum (Modules 1-19). Each one has a DBA analogy so you can map it to something you already know.

| Python Pattern | Example | DBA Analogy |
|---------------|---------|-------------|
| `import X` | `import numpy` | `USE database` or `SET search_path` - loads a library so you can use it |
| `from X import Y` | `from sklearn import metrics` | Like importing a specific function from a schema |
| `import X as Y` | `import numpy as np` | An alias - like `SELECT col AS alias` |
| f-string | `f"Count: {total}"` | `format()` in PL/pgSQL or string concatenation with `\|\|` |
| List comprehension | `[x for x in items if x > 10]` | `SELECT x FROM items WHERE x > 10` |
| Dict comprehension | `{k: v for k, v in items}` | `SELECT key, value FROM items` - result is a lookup table |
| Counting pattern | `sum(1 for x in items if x > 0)` | `SELECT COUNT(*) FROM items WHERE x > 0` |
| `.get(key, default)` | `d.get("port", 5432)` | `COALESCE(port, 5432)` |
| `lambda` | `lambda x: x[1]` | Tiny unnamed function - like an inline expression in `ORDER BY` |
| `sorted()` | `sorted(items, key=lambda x: x[1])` | `ORDER BY column DESC` |
| `zip(a, b)` | `zip(names, scores)` | Joining two arrays by position |
| `enumerate(items)` | `for i, item in enumerate(items)` | `ROW_NUMBER() OVER()` - loop with index counter |
| Tuple unpacking | `a, b = function()` | `SELECT col1, col2 INTO var1, var2` |
| `set()` | `set(items)` | `SELECT DISTINCT` - collection with no duplicates |
| `try/except` | `try: ... except: ...` | `BEGIN...EXCEPTION WHEN...END` in PL/pgSQL |
| Slice notation | `items[:5]`, `items[-3:]` | `LIMIT 5`, last 3 rows - `items[:5]` first 5, `items[5:]` after 5th, `items[-3:]` last 3 |
| `class` | `class Pipeline:` | `CREATE TYPE` - defines a blueprint/template |
| `self` | `self.conn = ...` | Like `NEW` in a trigger - refers to the current instance |
| `__init__` | `def __init__(self):` | Constructor - like `DEFAULT` values, runs when you create an instance |
| `@decorator` | `@mcp.tool()` | Like a trigger that wraps a function with extra behavior |
| `**kwargs` | `**block.input` | Unpack a dict as named arguments - like passing JSONB fields as function parameters |

> **You don't need to memorize these.** Come back to this reference when you see a pattern you don't recognize.

---

## Step 1. Create your first array

An array is just a list of numbers - but way faster than a Python list. Think of it like a column in a database table.

On your **Mac terminal**, run:

```bash
python3 -c "
import numpy as np    # 'as np' means 'I'll call it np for short' - like a SQL alias

a = np.array([1, 2, 3, 4, 5])
print('Array:', a)
print('Type:', type(a))
print('Shape:', a.shape)
print('Dtype:', a.dtype)
"
```

Expected output (yours will differ):
```
Array: [1 2 3 4 5]
Type: <class 'numpy.ndarray'>
Shape: (5,)
Dtype: int64
```

- `np.array()` turns a Python list into a NumPy array
- `shape` tells you the dimensions - `(5,)` means "5 elements, 1 dimension"
- `dtype` is the data type - `int64` means 64-bit integers

---

## Step 2. Create a 2D array (a table)

A 2D array has rows and columns - just like a SQL table.

```bash
python3 -c "
import numpy as np

table = np.array([
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
])
print('2D Array:')
print(table)
print('Shape:', table.shape)
print('Row 0:', table[0])
print('Column 1:', table[:, 1])
print('Element [1,2]:', table[1, 2])
"
```

Expected output:
```
2D Array:
[[1 2 3]
 [4 5 6]
 [7 8 9]]
Shape: (3, 3)
Row 0: [1 2 3]
Column 1: [2 5 8]
Element [1,2]: 6
```

- `shape (3, 3)` means 3 rows, 3 columns
- `table[0]` gets the first row (like `LIMIT 1`)
- `table[:, 1]` gets the second column (the `:` means "all rows")
- `table[1, 2]` gets row 1, column 2 (value: 6)

---

## Step 3. Do math on arrays

In SQL you write `SELECT AVG(duration) FROM queries`. In NumPy, you call `.mean()` on an array. The database handles the loop internally - NumPy does the same thing.

```bash
python3 -c "
import numpy as np

a = np.array([10, 20, 30, 40, 50])
print('Original:', a)
print('Add 5:', a + 5)
print('Multiply by 2:', a * 2)
print('Mean:', a.mean())
print('Sum:', a.sum())
print('Max:', a.max())
print('Min:', a.min())
print('Std Dev:', a.std())
"
```

Expected output:
```
Original: [10 20 30 40 50]
Add 5: [15 25 35 45 55]
Multiply by 2: [ 20  40  60  80 100]
Mean: 30.0
Sum: 150
Max: 50
Min: 10
Std Dev: 14.142135623730951
```

- `a + 5` adds 5 to EVERY element at once (no loop needed). This is **vectorization**.
- `.mean()`, `.sum()`, `.max()`, `.min()`, `.std()` work like their SQL equivalents

---

## Step 4. Reshape and create special arrays

Models expect data in specific shapes. Reshaping converts between shapes without changing the data.

```bash
python3 -c "
import numpy as np

a = np.array([1, 2, 3, 4, 5, 6])
print('Original:', a)
print('Shape:', a.shape)

reshaped = a.reshape(2, 3)
print('Reshaped to 2x3:')
print(reshaped)
print('Shape:', reshaped.shape)

print()
print('Zeros (2,3):')
print(np.zeros((2, 3)))
print('Random (2,3):')
np.random.seed(42)
print(np.random.rand(2, 3).round(2))
"
```

Expected output:
```
Original: [1 2 3 4 5 6]
Shape: (6,)
Reshaped to 2x3:
[[1 2 3]
 [4 5 6]]
Shape: (2, 3)

Zeros (2,3):
[[0. 0. 0.]
 [0. 0. 0.]]
Random (2,3):
[[0.37 0.95 0.73]
 [0.6  0.16 0.16]]
```

- `reshape(2, 3)` turns 6 elements into 2 rows x 3 columns. Total must match (2 x 3 = 6).
- `np.zeros()` creates an array filled with zeros - used to initialize model weights
- `np.random.rand()` creates random numbers between 0 and 1 - used for random initialization
- `np.random.seed(42)` makes random numbers reproducible (same seed = same numbers every time)

---

## Step 5. The dot product (critical for AI)

This is the single most important operation in AI. When you search for similar documents, compare embeddings, or run a neural network - it's all dot products.

A **dot product** multiplies matching elements and sums the results. Higher score = more similar.

```bash
python3 -c "
import numpy as np

query = np.array([0.8, 0.1, 0.3])
doc1  = np.array([0.7, 0.2, 0.4])
doc2  = np.array([0.1, 0.9, 0.2])

score1 = np.dot(query, doc1)
score2 = np.dot(query, doc2)

print('Query embedding:', query)
print('Doc1 embedding: ', doc1)
print('Doc2 embedding: ', doc2)
print()
print('Similarity (query vs doc1):', round(score1, 4))
print('Similarity (query vs doc2):', round(score2, 4))
print('Most similar: Doc1' if score1 > score2 else 'Most similar: Doc2')
"
```

Expected output:
```
Query embedding: [0.8 0.1 0.3]
Doc1 embedding:  [0.7 0.2 0.4]
Doc2 embedding:  [0.1 0.9 0.2]

Similarity (query vs doc1): 0.7
Similarity (query vs doc2): 0.23
Most similar: Doc1
```

Here's what happened:
- Each "embedding" is a list of numbers that represents the meaning of a document
- `np.dot(query, doc1)` = (0.8 x 0.7) + (0.1 x 0.2) + (0.3 x 0.4) = 0.56 + 0.02 + 0.12 = **0.70**
- `np.dot(query, doc2)` = (0.8 x 0.1) + (0.1 x 0.9) + (0.3 x 0.2) = 0.08 + 0.09 + 0.06 = **0.23**
- Doc1 scored higher - it's more similar to the query

This is exactly how RAG works. When you ask a question, your question gets turned into numbers, and the system finds which documents have the most similar numbers. That's Module 03.

---

## What You Learned

| Concept | What It Does | Why It Matters for AI |
|---------|-------------|----------------------|
| `np.array()` | Creates a fast numeric array | All AI data is stored as arrays |
| `shape` | Dimensions of the array | Models expect specific shapes |
| Vectorized math | Math on entire arrays at once | 100x faster than Python loops |
| `reshape()` | Change array dimensions | Feed data into models correctly |
| `np.dot()` | Dot product (similarity score) | Core operation in embeddings, neural nets, RAG |
