# Concepts 2.2: Linear Algebra for AI

**Tier 2 - Mathematics and statistics for AI.** Teaching reference. Linear algebra is the language AI actually speaks. Embeddings are vectors. Neural network layers are matrix multiplications. Similarity search is a dot product. If you get comfortable here, most of modern AI stops looking like magic.

**Who this is for:** DBAs. A vector is a row. A matrix is a table. Matrix multiplication is a very structured join-and-aggregate. We lean on that intuition the whole way.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

Then paste. `exit()` to leave. All snippets assume you ran `import numpy as np` first.

---

## 1. Scalars, vectors, matrices

- A **scalar** is a single number: `5`, `3.14`, `-2`. One value.
- A **vector** is an ordered list of numbers: `[2, 4, 6]`. Think of one row in a table, or one point in space.
- A **matrix** is a grid of numbers: rows and columns. Think of a whole table.

```python
import numpy as np

scalar = 5
vector = np.array([2, 4, 6])
matrix = np.array([[1, 2, 3],
                   [4, 5, 6]])

print(vector.shape)
print(matrix.shape)
```

Expected output (yours will differ):

```
(3,)
(2, 3)
```

`shape` is the single most useful attribute in AI code. `(3,)` means a vector of length 3. `(2, 3)` means 2 rows and 3 columns. When AI code crashes, 90% of the time it is a shape mismatch. Always print the shape.

In AI, a word or a sentence gets turned into a vector called an **embedding** (often 384, 768, or 1536 numbers long). A batch of embeddings is a matrix.

---

## 2. Matrix and vector operations

You can add vectors of the same length and multiply a vector by a scalar. NumPy does these element by element:

```python
a = np.array([1, 2, 3])
b = np.array([10, 20, 30])

print(a + b)
print(2 * a)
```

Expected output:

```
[11 22 33]
[2 4 6]
```

`a + b` added position by position. `2 * a` scaled every element. This element-wise behavior is why NumPy is fast: no Python loop, the whole array is processed at once (this is called **vectorization**, and it is the reason we use NumPy instead of raw loops).

---

## 3. The dot product

The **dot product** of two vectors: multiply them position by position, then add up the results. One number comes out.

```
[1, 2, 3] . [4, 5, 6] = 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
```

```python
a = np.array([1, 2, 3])
b = np.array([4, 5, 6])
np.dot(a, b)
```

Expected output:

```
32
```

The dot product is the workhorse of AI. It measures how much two vectors "agree". A large positive dot product means the vectors point the same way. A dot product of zero means the vectors are perpendicular (orthogonal), which we read as unrelated. Negative means they point in opposing directions (see: MathWorld Dot Product). Formally `a . b = |a| |b| cos(theta)`, where theta is the angle between them - that identity is what the next two sections build on. Every neuron in a neural network computes a dot product of its inputs and its weights.

---

## 4. Transpose

The **transpose** flips a matrix over its diagonal: rows become columns. A `(2, 3)` matrix becomes `(3, 2)`. In NumPy it is `.T`:

```python
m = np.array([[1, 2, 3],
              [4, 5, 6]])
print(m.T)
print(m.T.shape)
```

Expected output:

```
[[1 4]
 [2 5]
 [3 6]]
(3, 2)
```

You transpose constantly to line up shapes so matrices can be multiplied.

---

## 5. Matrix multiplication

This is the operation that runs neural networks. To multiply matrix `A` by matrix `B`, the number of **columns in A** must equal the number of **rows in B**. Each entry of the result is a dot product of a row of A with a column of B.

Rule of thumb for shapes: `(m, n) x (n, p) = (m, p)`. The inner numbers must match; the outer numbers become the result shape (see: MathWorld Matrix Multiplication). Note matrix multiplication is not commutative: `A @ B` is generally not equal to `B @ A`.

```python
A = np.array([[1, 2],
              [3, 4]])
B = np.array([[5, 6],
              [7, 8]])
np.matmul(A, B)
```

Expected output:

```
[[19 22]
 [43 50]]
```

The top-left `19` is the dot product of A's first row `[1, 2]` with B's first column `[5, 7]`: `1*5 + 2*7 = 19`. In Python you can also write `A @ B`, which is the same as `np.matmul`. A neural network layer is literally `output = inputs @ weights + bias`.

---

## 6. Vector distance

How far apart are two points? The **Euclidean distance** is the straight-line distance, the Pythagorean theorem in any number of dimensions: square the differences, add them, take the square root.

```python
a = np.array([1, 2])
b = np.array([4, 6])
dist = np.sqrt(np.sum((a - b) ** 2))
print(dist)
```

Expected output:

```
5.0

```

NumPy has a shortcut, `np.linalg.norm(a - b)`, that does the same thing: by default `np.linalg.norm` computes the L2 (Euclidean) norm (see: numpy.linalg.norm docs). Distance answers "how different are these two embeddings?" - the basis of nearest-neighbor search and clustering.

---

## 7. Cosine similarity

Distance cares about magnitude. Often we care only about **direction**: do these two vectors point the same way, regardless of length? That is **cosine similarity**:

```
cosine_similarity(a, b) = (a . b) / (norm(a) * norm(b))
```

It ranges from -1 (opposite) through 0 (unrelated) to 1 (identical direction).

```python
a = np.array([1, 2, 3])
b = np.array([2, 4, 6])   # same direction as a, just scaled
cos = np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))
print(round(cos, 4))
```

Expected output:

```
1.0
```

`b` is just `2 * a`, so they point in exactly the same direction and cosine is 1.0. This is THE metric for semantic search and RAG: turn a query into a vector, find the stored vectors with the highest cosine similarity, return those documents. You will implement this by hand in the BUILD lab.

---

## 8. Eigenvalue intuition (no heavy math)

Every (square) matrix, when applied to a vector, generally stretches and rotates it. For a special few vectors, the matrix does not change their direction line at all - it only scales them (a negative eigenvalue also flips them to point the opposite way along that same line). Those special vectors are **eigenvectors**, and the scaling factor is the **eigenvalue**: `A v = lambda v` (see: MathWorld Eigenvector).

Why you care: eigenvalues tell you the "main directions" and "strengths" hidden in data. **PCA** (Principal Component Analysis), the classic tool for shrinking high-dimensional data down to a few important directions, is built on eigenvectors. You do not need to compute them by hand. Just know: big eigenvalue = important direction, small eigenvalue = direction you can probably drop.

```python
M = np.array([[2, 0],
              [0, 3]])
values, vectors = np.linalg.eig(M)
print(values)
```

Expected output:

```
[2. 3.]
```

This diagonal matrix stretches the x-axis by 2 and the y-axis by 3, so the eigenvalues are exactly 2 and 3.

---

## 9. Dimensionality: why it matters

The **dimension** of a vector is how many numbers it has. An embedding with 768 numbers lives in 768-dimensional space. You cannot picture that, and you do not need to; the same dot product and cosine formulas work in any number of dimensions.

Two big reasons dimension matters:

- **More dimensions capture more meaning.** A 2-number embedding can barely tell cat from car. A 768-number embedding can capture tone, topic, and nuance. This is why good text models use hundreds of dimensions.
- **The curse of dimensionality.** In very high dimensions, distances become less meaningful (everything looks roughly equidistant), data gets sparse, and computation gets expensive. This is why we sometimes reduce dimensions (PCA) and why we pick embedding sizes carefully rather than just going bigger.

A neural network's "hidden size" is a dimension count. When you read that a model has a 4096-dimensional hidden state, that is the length of the vector flowing through it.

---

## Key takeaways

- Scalar = one number, vector = a row, matrix = a table. Always check `.shape`.
- Dot product = multiply-and-sum = how much two vectors agree. It is everywhere.
- Matrix multiplication `(m,n) x (n,p) = (m,p)` is what a neural network layer does.
- Euclidean distance = how far apart; cosine similarity = same direction (the metric for search and RAG).
- Eigenvalues = the main directions and their strengths (used by PCA).
- Dimensionality: more captures more meaning, but too much gets sparse and expensive.

Next: **Concepts 2.3 - Probability**, where we start reasoning about uncertainty, the thing every model output really is.

---

## References

- MathWorld, Dot Product (a . b = |a||b|cos theta; zero = orthogonal): https://mathworld.wolfram.com/DotProduct.html
- MathWorld, Matrix Multiplication (inner-dimension rule): https://mathworld.wolfram.com/MatrixMultiplication.html
- MathWorld, Eigenvector and Eigenvalue (A v = lambda v): https://mathworld.wolfram.com/Eigenvector.html
- numpy.matmul / the @ operator: https://numpy.org/doc/stable/reference/generated/numpy.matmul.html
- numpy.dot: https://numpy.org/doc/stable/reference/generated/numpy.dot.html
- numpy.linalg.norm (default L2 norm): https://numpy.org/doc/stable/reference/generated/numpy.linalg.norm.html
- numpy.linalg.eig: https://numpy.org/doc/stable/reference/generated/numpy.linalg.eig.html
- scikit-learn, PCA: https://scikit-learn.org/stable/modules/generated/sklearn.decomposition.PCA.html
