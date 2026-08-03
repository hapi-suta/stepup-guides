# Build 01: Vectors - Your Data Lives Here

Every piece of data in AI - text, images, audio - gets converted into vectors. A vector is just a list of numbers. That's it. If you understand a row in a SQL result, you already understand vectors.

---

## Step 1. What is a vector?

A vector is a list of numbers. Nothing more.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
# A vector is just a list of numbers
# Think of it like ONE ROW from a SQL query result

# This is a vector with 3 numbers:
server_stats = [92.5, 68.3, 285]
#                ^      ^     ^
#               CPU   Memory  Connections
#            (percent) (percent) (count)

# Print it
print("Server stats vector:", server_stats)

# How many numbers in this vector? That's called the "dimension"
# len() counts how many items are in a list
print("Dimensions:", len(server_stats))

# You can access each number by its position (starts at 0, not 1)
print("CPU (position 0):", server_stats[0])
print("Memory (position 1):", server_stats[1])
print("Connections (position 2):", server_stats[2])
PYEOF
```

Expected output (yours will differ):
```
Server stats vector: [92.5, 68.3, 285]
Dimensions: 3
CPU (position 0): 92.5
Memory (position 1): 68.3
Connections (position 2): 285
```

That's a 3-dimensional vector. "Dimensional" just means "how many numbers in the list."

In Module 03, your embeddings were 384-dimensional vectors - lists of 384 numbers. Same concept, just longer.

---

## Step 2. Create vectors with NumPy

Python lists work for small vectors, but AI uses NumPy arrays because they're much faster with large datasets.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
# NumPy is a library (a collection of pre-built code) for working with numbers
# "import" means "load this library so I can use it"
# "as np" means "I'll call it 'np' for short instead of typing 'numpy' every time"
import numpy as np

# Create a vector using NumPy
# np.array() converts a regular list into a NumPy array
server_a = np.array([92.5, 68.3, 285.0])
server_b = np.array([15.2, 42.1, 25.0])

# Print them
# f"..." is called an f-string - it lets you put variables inside text
# {server_a} gets replaced with the actual value of server_a
print(f"Server A (sick):    {server_a}")
print(f"Server B (healthy): {server_b}")

# NumPy tells you the shape (how many numbers)
# .shape is a property - like checking a column's data type
print(f"Shape: {server_a.shape}")
# (3,) means "3 numbers in one dimension" - a 1D vector

# What type of numbers?
# .dtype is like checking if a column is INTEGER or FLOAT
print(f"Data type: {server_a.dtype}")
# float64 means "decimal number with high precision"
PYEOF
```

Expected output (yours will differ):
```
Server A (sick):    [ 92.5  68.3 285. ]
Server B (healthy): [ 15.2  42.1  25. ]
Shape: (3,)
Data type: float64
```

---

## Step 3. Vector math - adding and scaling

The power of NumPy: math operations work on ALL numbers at once. No loops needed.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

server_a = np.array([92.5, 68.3, 285.0])   # CPU, Memory, Connections
server_b = np.array([15.2, 42.1, 25.0])

# --- Addition: add two vectors (element by element) ---
# Position 0 + Position 0, Position 1 + Position 1, etc.
combined = server_a + server_b
print("Addition (element by element):")
print(f"  {server_a}")
print(f"+ {server_b}")
print(f"= {combined}")
# 92.5+15.2=107.7, 68.3+42.1=110.4, 285+25=310
print()

# --- Subtraction: difference between two vectors ---
diff = server_a - server_b
print("Subtraction (how different are they?):")
print(f"  {server_a}")
print(f"- {server_b}")
print(f"= {diff}")
print()

# --- Scaling: multiply every number by a constant ---
# "Scaling" means making the vector bigger or smaller
# Like converting bytes to kilobytes - every number gets divided
half = server_a * 0.5
print("Scaling (multiply every number by 0.5):")
print(f"  {server_a} * 0.5")
print(f"= {half}")
print()

# --- Why this matters for AI ---
# In a neural network, inputs get multiplied by "weights" (scaling)
# Then results from different layers get added together (addition)
# That's it. Neural networks are just lots of multiply and add.
print("Neural network in a nutshell:")
print("  input * weight + bias = output")
print("  That's vector math.")
PYEOF
```

Expected output (yours will differ):
```
Addition (element by element):
  [92.5 68.3 285.]
+ [15.2 42.1 25.]
= [107.7 110.4 310. ]

Subtraction (how different are they?):
  [92.5 68.3 285.]
- [15.2 42.1 25.]
= [ 77.3  26.2 260. ]

Scaling (multiply every number by 0.5):
  [92.5 68.3 285.] * 0.5
= [ 46.25  34.15 142.5 ]

Neural network in a nutshell:
  input * weight + bias = output
  That's vector math.
```

---

## Step 4. Distance - how far apart are two vectors?

This is how AI measures similarity. Two vectors that are "close" are similar. Two vectors that are "far" are different.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# Three servers with their stats: [CPU%, Memory%, Connections]
sick_server    = np.array([95.0, 88.0, 290.0])
healthy_server = np.array([15.0, 40.0, 25.0])
another_sick   = np.array([92.0, 85.0, 280.0])

# --- Euclidean distance ---
# "How far apart are two points?"
# Like measuring the straight-line distance between two cities on a map
#
# The formula:
#   1. Subtract the vectors (get the difference at each position)
#   2. Square each difference (make everything positive)
#   3. Add up all the squares
#   4. Take the square root
#
# np.sqrt() = square root
# np.sum() = add up all the numbers
# ** 2 = "squared" (multiply a number by itself)

def distance(a, b):
    """Calculate Euclidean distance between two vectors."""
    return np.sqrt(np.sum((a - b) ** 2))

# Which servers are most similar?
d1 = distance(sick_server, healthy_server)
d2 = distance(sick_server, another_sick)
d3 = distance(healthy_server, another_sick)

print("Distance between servers:")
print(f"  Sick vs Healthy:      {d1:.1f}  (far apart = very different)")
print(f"  Sick vs Another Sick: {d2:.1f}   (close = similar)")
print(f"  Healthy vs Another:   {d3:.1f}  (far apart = very different)")
print()

# Smaller distance = more similar
# This is EXACTLY how pgvector finds similar documents!
# In Module 03, the <=> operator calculated distance between embeddings
print("Connection to Module 03 (RAG):")
print("  SELECT * FROM documents ORDER BY embedding <=> query_vector;")
print("  The <=> operator calculates distance between two vectors.")
print("  Closest vectors = most relevant documents.")
PYEOF
```

Expected output (yours will differ):
```
Distance between servers:
  Sick vs Healthy:      311.5  (far apart = very different)
  Sick vs Another Sick: 11.2   (close = similar)
  Healthy vs Another:   300.4  (far apart = very different)

Connection to Module 03 (RAG):
  SELECT * FROM documents ORDER BY embedding <=> query_vector;
  The <=> operator calculates distance between two vectors.
  Closest vectors = most relevant documents.
```

---

## Step 5. Dot product - the most important operation in AI

The dot product is how AI measures similarity. It's used in embeddings, attention (transformers), and every neural network layer.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- What is a dot product? ---
# Multiply matching positions, then add everything up.
#
# Like a SQL query:
#   SELECT SUM(a.value * b.weight)
#   FROM a JOIN b ON a.position = b.position;

a = np.array([1, 2, 3])
b = np.array([4, 5, 6])

# Step by step:
#   Position 0: 1 * 4 = 4
#   Position 1: 2 * 5 = 10
#   Position 2: 3 * 6 = 18
#   Sum: 4 + 10 + 18 = 32

# np.dot() calculates the dot product
result = np.dot(a, b)
print("Dot product step by step:")
print(f"  a = {a}")
print(f"  b = {b}")
print(f"  (1*4) + (2*5) + (3*6) = {1*4} + {2*5} + {3*6} = {result}")
print()

# --- Why does AI care? ---
# Dot product measures how much two vectors "agree"
# High dot product = vectors point the same direction = SIMILAR
# Low/negative dot product = vectors point different directions = DIFFERENT

# Example: Movie preferences
# Each number = how much you like [Action, Comedy, Drama]
alice = np.array([5, 1, 1])     # loves action, meh on comedy/drama
bob   = np.array([4, 2, 1])     # also loves action
carol = np.array([1, 1, 5])     # loves drama

print("Movie preference similarity (dot product):")
print(f"  Alice vs Bob:   {np.dot(alice, bob)}")
print(f"  Alice vs Carol: {np.dot(alice, carol)}")
print(f"  Bob vs Carol:   {np.dot(bob, carol)}")
print()
print("  Alice and Bob are most similar (highest dot product)")
print("  This is how recommendation systems work!")
print()

# --- Connection to embeddings ---
# In Module 03, cosine similarity used the dot product:
#   cosine_similarity = dot(a, b) / (length(a) * length(b))
# It's a normalized dot product - scales the result between -1 and 1

# np.linalg.norm() calculates the "length" of a vector
# (square root of sum of squares)
def cosine_similarity(a, b):
    """Same calculation pgvector uses with <=> operator."""
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))

print("Cosine similarity (normalized dot product):")
print(f"  Alice vs Bob:   {cosine_similarity(alice, bob):.4f}")
print(f"  Alice vs Carol: {cosine_similarity(alice, carol):.4f}")
print(f"  Bob vs Carol:   {cosine_similarity(bob, carol):.4f}")
print()
print("  1.0 = identical, 0.0 = unrelated, -1.0 = opposite")
PYEOF
```

Expected output (yours will differ):
```
Dot product step by step:
  a = [1 2 3]
  b = [4 5 6]
  (1*4) + (2*5) + (3*6) = 4 + 10 + 18 = 32

Movie preference similarity (dot product):
  Alice vs Bob:   24
  Alice vs Carol: 11
  Bob vs Carol:   11

  Alice and Bob are most similar (highest dot product)
  This is how recommendation systems work!

Cosine similarity (normalized dot product):
  Alice vs Bob:   0.9813
  Alice vs Carol: 0.5345
  Bob vs Carol:   0.5963

  1.0 = identical, 0.0 = unrelated, -1.0 = opposite
```

---

## Step 6. Real embeddings - vectors in the wild

Let's connect this to real AI. Embeddings from Module 03 are vectors - and everything we just learned applies to them.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# Simulated embeddings (in Module 03, sentence-transformers generated these)
# Each embedding is a vector with 384 numbers representing meaning
# Here we use 5 numbers to keep it readable

# These fake embeddings capture the IDEA that similar topics
# have similar numbers
backup_doc   = np.array([0.8, 0.1, 0.9, 0.2, 0.1])  # backup-related
restore_doc  = np.array([0.7, 0.2, 0.8, 0.3, 0.1])  # also backup-related
replication_doc = np.array([0.1, 0.9, 0.2, 0.8, 0.7])  # replication-related
cooking_doc  = np.array([0.1, 0.1, 0.1, 0.1, 0.9])  # totally unrelated

# User's question (also converted to a vector)
query = np.array([0.9, 0.1, 0.8, 0.2, 0.0])  # "how do I restore a backup?"

# Calculate similarity using cosine similarity (same as pgvector <=>)
def cosine_sim(a, b):
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))

print("Query: 'How do I restore a backup?'")
print()
print("Similarity scores:")

# Create a list of (name, score) pairs and sort by score
# This is like: SELECT doc, similarity FROM docs ORDER BY similarity DESC
docs = [
    ("backup-guide", backup_doc),
    ("restore-guide", restore_doc),
    ("replication-guide", replication_doc),
    ("cooking-recipe", cooking_doc),
]

# sorted() puts items in order
# lambda is a tiny function without a name, written on one line.
# lambda x: x[1] means "a function that takes x and returns x[1]"
# It's the same as writing: def get_second(x): return x[1]
# key=lambda x: x[1] tells sorted() to sort by the second item (the score)
# DBA analogy: like an inline expression in ORDER BY
# reverse=True means "highest first"
results = sorted(
    [(name, cosine_sim(query, vec)) for name, vec in docs],
    key=lambda x: x[1],
    reverse=True
)

for name, score in results:
    # :.4f means "show 4 decimal places"
    bar = "#" * int(score * 20)  # visual bar
    print(f"  {score:.4f} {bar:20s} {name}")

print()
print("The backup and restore guides are most similar to the query.")
print("This is EXACTLY what your RAG pipeline does in Module 03!")
print()
print("In SQL terms:")
print("  SELECT source, 1 - (embedding <=> query) AS similarity")
print("  FROM documents")
print("  ORDER BY embedding <=> query")
print("  LIMIT 3;")
PYEOF
```

Expected output (yours will differ):
```
Query: 'How do I restore a backup?'

Similarity scores:
  0.9916 ###################  backup-guide
  0.9724 ##################   restore-guide
  0.4553 #########            replication-guide
  0.2099 ####                 cooking-recipe

The backup and restore guides are most similar to the query.
This is EXACTLY what your RAG pipeline does in Module 03!

In SQL terms:
  SELECT source, 1 - (embedding <=> query) AS similarity
  FROM documents
  ORDER BY embedding <=> query
  LIMIT 3;
```

---

## What You Learned

| Concept | What It Is | DBA Analogy | AI Use |
|---------|-----------|-------------|--------|
| Vector | A list of numbers | One row from a query | Embeddings, model inputs |
| Dimension | How many numbers in the vector | Number of columns | 384 for MiniLM, 1536 for OpenAI |
| Vector addition | Add matching positions | Combining two result sets | Combining features |
| Scaling | Multiply every number | Unit conversion | Adjusting weights |
| Distance | How far apart two vectors are | Difference between two rows | Finding similar documents |
| Dot product | Multiply + sum | `SUM(a.val * b.val)` after JOIN | Similarity, attention, every NN layer |
| Cosine similarity | Normalized dot product | pgvector `<=>` operator | RAG search, embeddings |
