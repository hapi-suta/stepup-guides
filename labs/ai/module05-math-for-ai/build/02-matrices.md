# Build 02: Matrices - Tables of Numbers

A matrix is a table. You already think in tables every day. Neural networks are just chains of matrix operations - multiply one table of numbers by another to get a result.

---

## Step 1. What is a matrix?

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# A matrix is a 2D table of numbers
# Think of it as a SQL result set:
#
#   SELECT cpu, memory, connections FROM server_metrics;
#
#   cpu  | memory | connections
#   -----+--------+------------
#   92.5 |  68.3  |    285       <- row 0 (server A)
#   15.2 |  42.1  |     25       <- row 1 (server B)
#   55.0 |  51.0  |    150       <- row 2 (server C)

# np.array() with nested lists creates a matrix
# Each inner list [...] is one row
metrics = np.array([
    [92.5, 68.3, 285],   # server A
    [15.2, 42.1,  25],   # server B
    [55.0, 51.0, 150],   # server C
])

print("Server metrics matrix:")
print(metrics)
print()

# .shape tells you (rows, columns) - like counting rows and columns in a query result
print(f"Shape: {metrics.shape}")
print(f"  {metrics.shape[0]} rows (servers)")
print(f"  {metrics.shape[1]} columns (metrics)")
print()

# Access individual values: matrix[row, column]
# Just like a spreadsheet: row first, then column
print(f"Server A's CPU (row 0, col 0): {metrics[0, 0]}")
print(f"Server B's memory (row 1, col 1): {metrics[1, 1]}")
print(f"Server C's connections (row 2, col 2): {metrics[2, 2]}")
print()

# Access an entire row (one server's stats)
# metrics[1] means "give me all of row 1"
print(f"Server B (all metrics): {metrics[1]}")

# Access an entire column (one metric across all servers)
# metrics[:, 0] means "all rows, column 0"
# The : means "all" - like SELECT * but for rows
print(f"All CPUs (column 0): {metrics[:, 0]}")
PYEOF
```

Expected output (yours will differ):
```
Server metrics matrix:
[[ 92.5  68.3 285. ]
 [ 15.2  42.1  25. ]
 [ 55.   51.  150. ]]

Shape: (3, 3)
  3 rows (servers)
  3 columns (metrics)

Server A's CPU (row 0, col 0): 92.5
Server B's memory (row 1, col 1): 42.1
Server C's connections (row 2, col 2): 150.0

Server B (all metrics): [15.2 42.1 25. ]
All CPUs (column 0): [92.5 15.2 55. ]
```

---

## Step 2. Matrix math - operations on entire tables

Just like vectors, NumPy lets you do math on entire matrices at once. No row-by-row loops needed.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# Morning metrics
morning = np.array([
    [45.0, 50.0, 100],   # server A
    [12.0, 38.0,  20],   # server B
])

# Evening metrics
evening = np.array([
    [92.5, 68.3, 285],   # server A
    [15.2, 42.1,  25],   # server B
])

# --- Element-wise operations (same position = same position) ---

# Difference: how much did each metric change?
change = evening - morning
print("Change from morning to evening:")
print(change)
print("  Server A: CPU went up 47.5%, Memory up 18.3%, Connections up 185")
print()

# Average of morning and evening (daily average)
# Adding two matrices, then dividing by 2
daily_avg = (morning + evening) / 2
print("Daily average:")
print(daily_avg)
print()

# --- Aggregate operations ---

# Average across all servers (like GROUP BY with AVG)
# axis=0 means "collapse the rows" (average down each column)
col_avg = np.mean(evening, axis=0)
print(f"Average across servers: {col_avg}")
print("  (avg CPU, avg Memory, avg Connections)")
print()

# Average across all metrics for each server
# axis=1 means "collapse the columns" (average across each row)
row_avg = np.mean(evening, axis=1)
print(f"Average per server: {row_avg}")
print("  (Server A's avg, Server B's avg)")
print()

# --- SQL equivalent ---
print("SQL equivalent of axis=0 (column averages):")
print("  SELECT avg(cpu), avg(memory), avg(connections)")
print("  FROM metrics;")
print()
print("SQL equivalent of axis=1 (row averages):")
print("  SELECT server, avg(value)")
print("  FROM metrics_unpivoted")
print("  GROUP BY server;")
PYEOF
```

Expected output (yours will differ):
```
Change from morning to evening:
[[ 47.5  18.3 185. ]
 [  3.2   4.1   5. ]]
  Server A: CPU went up 47.5%, Memory up 18.3%, Connections up 185

Daily average:
[[ 68.75  59.15 192.5 ]
 [ 13.6   40.05  22.5 ]]

Average across servers: [53.85 55.2  155.  ]
  (avg CPU, avg Memory, avg Connections)

Average per server: [148.6   27.43]
  (Server A's avg, Server B's avg)

SQL equivalent of axis=0 (column averages):
  SELECT avg(cpu), avg(memory), avg(connections)
  FROM metrics;

SQL equivalent of axis=1 (row averages):
  SELECT server, avg(value)
  FROM metrics_unpivoted
  GROUP BY server;
```

---

## Step 3. Matrix multiplication - the core of neural networks

This is THE most important operation in AI. Every neural network layer is a matrix multiplication. When people say "GPU" or "tensor cores," they mean hardware optimized for this one operation.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- What is matrix multiplication? ---
# It's NOT multiplying matching positions (that's element-wise).
# Matrix multiplication combines rows from one matrix with columns from another.
#
# Think of it like this:
#   - You have INPUT data (servers with metrics)
#   - You have WEIGHTS (how important each metric is)
#   - Matrix multiply gives you a SCORE for each server
#
# This is EXACTLY what a neural network layer does.

# Input: 3 servers, each with 3 metrics (CPU, Memory, Connections)
# Shape: (3, 3) - 3 rows, 3 columns
inputs = np.array([
    [0.92, 0.68, 0.95],   # server A (normalized to 0-1 range)
    [0.15, 0.42, 0.08],   # server B
    [0.55, 0.51, 0.50],   # server C
])

# Weights: how much each metric matters for "health score"
# Shape: (3, 1) - 3 rows, 1 column
# These are like coefficients in a linear model
weights = np.array([
    [0.4],   # CPU matters a lot
    [0.2],   # Memory matters some
    [0.4],   # Connections matter a lot
])

# Matrix multiply: inputs @ weights
# The @ symbol means "matrix multiply" in Python
# For each server (row), it calculates:
#   CPU * 0.4 + Memory * 0.2 + Connections * 0.4
result = inputs @ weights

print("Inputs (3 servers x 3 metrics):")
print(inputs)
print()
print("Weights (importance of each metric):")
print(weights.flatten())  # .flatten() shows it as one line
print()
print("Result (health scores):")
# enumerate() gives us both the index (i) and value
# [0] gets the first (only) column from each row
for i, score in enumerate(result):
    label = ["Server A", "Server B", "Server C"][i]
    print(f"  {label}: {score[0]:.3f}")
print()

# Let's verify Server A by hand:
print("Verify Server A by hand:")
print(f"  CPU:    0.92 * 0.4 = {0.92 * 0.4:.3f}")
print(f"  Memory: 0.68 * 0.2 = {0.68 * 0.2:.3f}")
print(f"  Conns:  0.95 * 0.4 = {0.95 * 0.4:.3f}")
print(f"  Total:              = {0.92*0.4 + 0.68*0.2 + 0.95*0.4:.3f}")
print()

print("This is EXACTLY what a neural network layer does:")
print("  output = inputs @ weights + bias")
print("  That's it. The whole layer.")
PYEOF
```

Expected output (yours will differ):
```
Inputs (3 servers x 3 metrics):
[[0.92 0.68 0.95]
 [0.15 0.42 0.08]
 [0.55 0.51 0.5 ]]

Weights (importance of each metric):
[0.4 0.2 0.4]

Result (health scores):
  Server A: 0.884
  Server B: 0.176
  Server C: 0.422

Verify Server A by hand:
  CPU:    0.92 * 0.4 = 0.368
  Memory: 0.68 * 0.2 = 0.136
  Conns:  0.95 * 0.4 = 0.380
  Total:              = 0.884

This is EXACTLY what a neural network layer does:
  output = inputs @ weights + bias
  That's it. The whole layer.
```

---

## Step 4. Shape rules - when can you multiply?

Matrix multiplication has one rule: the inner dimensions must match. This is the most common error you'll see in AI code.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- The shape rule ---
# To multiply A @ B:
#   A is (rows_a, cols_a)
#   B is (rows_b, cols_b)
#   cols_a MUST equal rows_b
#   Result is (rows_a, cols_b)
#
# Think of it like a SQL JOIN:
#   Table A has 3 columns, Table B has 3 rows
#   They "match" on 3 -> you can join them

# Works: (3, 3) @ (3, 1) -> (3, 1)
# Inner dimensions: 3 == 3 ✓
A = np.array([[1, 2, 3], [4, 5, 6], [7, 8, 9]])  # (3, 3)
B = np.array([[1], [2], [3]])                       # (3, 1)
C = A @ B                                           # (3, 1)
print(f"A shape: {A.shape}")
print(f"B shape: {B.shape}")
print(f"A @ B shape: {C.shape}  <- works!")
print()

# Works: (2, 4) @ (4, 3) -> (2, 3)
# Inner dimensions: 4 == 4 ✓
D = np.ones((2, 4))    # np.ones() creates a matrix filled with 1s
E = np.ones((4, 3))
F = D @ E
print(f"D shape: {D.shape}")
print(f"E shape: {E.shape}")
print(f"D @ E shape: {F.shape}  <- works!")
print()

# FAILS: (3, 3) @ (2, 1) -> ERROR
# Inner dimensions: 3 != 2 ✗
print("What happens when shapes don't match:")
try:
    # try/except catches errors so the program doesn't crash
    # This is like TRY...CATCH in other languages
    bad = A @ np.ones((2, 1))
except ValueError as e:
    # 'e' contains the error message
    print(f"  Error: {e}")
    print("  Fix: reshape your data so inner dimensions match")
print()

# --- Neural network shapes ---
print("Neural network layer shapes:")
print("  Input:  (batch_size, input_features)")
print("  Weight: (input_features, output_features)")
print("  Output: (batch_size, output_features)")
print()
print("Example: 32 servers, each with 10 metrics, predicting 3 categories")
print("  Input:  (32, 10)  <- 32 servers, 10 metrics each")
print("  Weight: (10, 3)   <- transforms 10 inputs into 3 outputs")
print("  Output: (32, 3)   <- 32 servers, 3 category scores each")
PYEOF
```

Expected output (yours will differ):
```
A shape: (3, 3)
B shape: (3, 1)
A @ B shape: (3, 1)  <- works!

D shape: (2, 4)
E shape: (4, 3)
D @ E shape: (2, 3)  <- works!

What happens when shapes don't match:
  Error: matmul: Input operand 1 has a mismatch in its core dimension 0, with gufunc signature (n?,k),(k,m?)->(n?,m?) (size 2 is different from 3)
  Fix: reshape your data so inner dimensions match

Neural network layer shapes:
  Input:  (batch_size, input_features)
  Weight: (input_features, output_features)
  Output: (batch_size, output_features)

Example: 32 servers, each with 10 metrics, predicting 3 categories
  Input:  (32, 10)  <- 32 servers, 10 metrics each
  Weight: (10, 3)   <- transforms 10 inputs into 3 outputs
  Output: (32, 3)   <- 32 servers, 3 category scores each
```

---

## Step 5. Transpose and reshape - rearranging your data

Sometimes your data is in the wrong shape. Transpose flips rows and columns. Reshape rearranges without changing the data.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- Transpose: flip rows and columns ---
# Like pivoting a table in SQL
# ROWS become COLUMNS, COLUMNS become ROWS

metrics = np.array([
    [92.5, 68.3, 285],   # server A
    [15.2, 42.1,  25],   # server B
])
print("Original (2 servers x 3 metrics):")
print(metrics)
print(f"Shape: {metrics.shape}")
print()

# .T is the transpose
# Each server was a row -> now each server is a column
transposed = metrics.T
print("Transposed (3 metrics x 2 servers):")
print(transposed)
print(f"Shape: {transposed.shape}")
print()

# --- Reshape: same data, different shape ---
# Like changing how you display data without changing the data itself

# 12 numbers in a flat list
flat = np.array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
print(f"Flat: {flat}")
print(f"Shape: {flat.shape}")
print()

# Reshape into 3 rows x 4 columns
# .reshape(rows, columns)
table = flat.reshape(3, 4)
print("Reshaped to (3, 4):")
print(table)
print()

# Reshape into 4 rows x 3 columns
# Same 12 numbers, different arrangement
table2 = flat.reshape(4, 3)
print("Reshaped to (4, 3):")
print(table2)
print()

# Use -1 to let NumPy figure out one dimension
# "I want 6 columns, you figure out how many rows"
auto = flat.reshape(-1, 6)
print("Reshaped to (-1, 6) - NumPy figures out rows:")
print(auto)
print(f"Shape: {auto.shape}")
print()

print("Why reshape matters in AI:")
print("  Images come in as (height, width, colors)")
print("  Neural networks expect (batch, features)")
print("  You reshape to convert between formats")
PYEOF
```

Expected output (yours will differ):
```
Original (2 servers x 3 metrics):
[[ 92.5  68.3 285. ]
 [ 15.2  42.1  25. ]]
Shape: (2, 3)

Transposed (3 metrics x 2 servers):
[[ 92.5  15.2]
 [ 68.3  42.1]
 [285.    25. ]]
Shape: (3, 2)

Flat: [ 1  2  3  4  5  6  7  8  9 10 11 12]
Shape: (12,)

Reshaped to (3, 4):
[[ 1  2  3  4]
 [ 5  6  7  8]
 [ 9 10 11 12]]

Reshaped to (4, 3):
[[ 1  2  3]
 [ 4  5  6]
 [ 7  8  9]
 [10 11 12]]

Reshaped to (-1, 6) - NumPy figures out rows:
[[ 1  2  3  4  5  6]
 [ 7  8  9 10 11 12]]
Shape: (2, 6)

Why reshape matters in AI:
  Images come in as (height, width, colors)
  Neural networks expect (batch, features)
  You reshape to convert between formats
```

---

## What You Learned

| Concept | What It Is | DBA Analogy | AI Use |
|---------|-----------|-------------|--------|
| Matrix | 2D table of numbers | Query result set | Store model weights, batch data |
| Shape | (rows, columns) | Counting rows and columns | Must match for operations |
| Element-wise math | Operate on matching positions | Column arithmetic | Feature scaling, residuals |
| Matrix multiply (`@`) | Combine inputs with weights | Weighted JOIN | Every neural network layer |
| Shape rule | Inner dimensions must match | JOIN key compatibility | Most common AI error |
| Transpose (`.T`) | Flip rows and columns | PIVOT | Reshape for operations |
| Reshape | Same data, new arrangement | Different result display | Format data for model |
