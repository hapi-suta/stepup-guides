# Concepts 3.1: NumPy for AI

**Tier 3 - Data analysis and data engineering.** Teaching reference. NumPy is the foundation under pandas, scikit-learn, and every deep-learning library. When you hear "tensor," think "a NumPy array with more dimensions." As an AI consultant you rarely write raw NumPy all day, but you must read it, debug it, and understand why a shape mismatch just crashed a model.

**Who this is for:** DBAs. You think in tables and sets already. NumPy is the same idea - operate on a whole column at once instead of looping row by row - but for numbers in memory instead of rows on disk.

**Run the snippets:** on your **lab server** (CentOS Stream 9), as **ec2-user**:

```bash
python3.12
```

Type `exit()` to leave. Every snippet assumes you first ran `import numpy as np`.

---

## 1. Why NumPy exists

Plain Python is slow for math because a Python list holds boxed objects and every operation loops in the interpreter. NumPy stores numbers in a tight block of memory, all the same type, and runs the math in compiled C. This is called **vectorization**: you express "add 1 to every element" as one operation, not a loop.

The same idea you already trust in SQL. You never loop over rows to sum a column - you write `SUM(col)` and the engine does it in bulk. NumPy is that, in memory.

```python
import numpy as np
py_list = [1, 2, 3, 4]
print([x * 2 for x in py_list])   # the slow, loopy Python way

arr = np.array([1, 2, 3, 4])
print(arr * 2)                    # the fast, vectorized NumPy way
```

Expected output:

```
[2, 4, 6, 8]
[2 4 6 8]
```

Note the NumPy result prints with no commas - that is how you can tell an array from a list at a glance.

---

## 2. Creating arrays

```python
import numpy as np
print(np.array([1, 2, 3]))          # from a Python list
print(np.zeros(3))                  # three zeros
print(np.ones((2, 2)))              # 2 rows, 2 cols of ones
print(np.arange(0, 10, 2))          # like range(): start, stop, step
print(np.linspace(0, 1, 5))         # 5 evenly spaced numbers from 0 to 1
```

Expected output:

```
[1 2 3]
[0. 0. 0.]
[[1. 1.]
 [1. 1.]]
[0 2 4 6 8]
[0.   0.25 0.5  0.75 1.  ]
```

The trailing dots (`0.`) mean the values are floats (decimals). `arange` gives whole numbers here; `zeros`/`ones`/`linspace` default to floats.

---

## 3. Shape - the single most important idea

An array's **shape** is a tuple describing its dimensions. Almost every AI bug you will ever chase is a shape mismatch. Learn to read shapes and half your debugging is done.

```python
import numpy as np
a = np.array([1, 2, 3, 4, 5, 6])
print(a.shape)          # (6,) - a 1-D array of 6 elements

b = a.reshape(2, 3)     # rearrange into 2 rows, 3 cols
print(b)
print(b.shape)          # (2, 3)

print(b.ndim)           # 2 - number of dimensions
print(b.size)           # 6 - total elements
print(b.dtype)          # int64 - the element type
```

Expected output:

```
(6,)
[[1 2 3]
 [4 5 6]]
(2, 3)
2
6
int64
```

Read a shape left to right as "outermost to innermost." `(2, 3)` = 2 rows, each row has 3 numbers. A model that expects input shape `(batch, 784)` wants a 2-D array: `batch` rows, 784 numbers each. If you hand it `(784,)` it will complain.

---

## 4. Indexing and slicing

Same bracket syntax as Python lists, extended to multiple dimensions with commas.

```python
import numpy as np
a = np.array([10, 20, 30, 40, 50])
print(a[0])        # first element
print(a[-1])       # last element
print(a[1:4])      # elements 1, 2, 3 (stop is exclusive)

m = np.array([[1, 2, 3],
              [4, 5, 6],
              [7, 8, 9]])
print(m[0, 2])     # row 0, col 2 -> 3
print(m[:, 1])     # every row, col 1 -> the middle column
print(m[1, :])     # row 1, every col -> the middle row
```

Expected output:

```
10
50
[20 30 40]
3
[2 5 8]
[4 5 6]
```

`[row, col]` with `:` meaning "all of this axis." `m[:, 1]` = "all rows, column 1." This is exactly how you pull a feature column out of a data matrix.

---

## 5. Boolean masking - filtering without a loop

You can index an array with a True/False array to keep only the elements you want. This is NumPy's `WHERE` clause.

```python
import numpy as np
a = np.array([5, 12, 3, 20, 8, 15])
mask = a > 10           # a True/False array
print(mask)
print(a[mask])          # keep only where True
print(a[a > 10])        # same thing in one line
print((a > 10).sum())   # count how many pass (True counts as 1)
```

Expected output:

```
[False  True False  True False  True]
[12 20 15]
[12 20 15]
3
```

`(a > 10).sum()` counting Trues is the idiom for "how many rows match a condition" - the NumPy equivalent of `SELECT COUNT(*) WHERE a > 10`.

---

## 6. Broadcasting - the rule that trips everyone up

Broadcasting is how NumPy handles operations between arrays of different shapes. When shapes do not match, NumPy tries to "stretch" the smaller one to fit, without actually copying memory. Understanding this rule prevents most silent bugs.

The rule: compare shapes from the right. Two dimensions are compatible if they are equal, or one of them is 1.

```python
import numpy as np
prices = np.array([[100], [200], [300]])   # shape (3, 1)
discounts = np.array([0.9, 0.8, 0.5])      # shape (3,)
print(prices * discounts)                  # (3,1) * (3,) -> (3,3)
```

Expected output:

```
[[ 90.  80.  50.]
 [180. 160. 100.]
 [270. 240. 150.]]
```

NumPy stretched the `(3,1)` column and the `(3,)` row into a `(3,3)` grid and multiplied every combination. This is powerful and dangerous: if you did not mean to build a 3x3 grid, you have a bug that runs silently. When a result has a surprising shape, suspect broadcasting.

The simplest, safest broadcast is array-with-scalar:

```python
import numpy as np
celsius = np.array([0, 20, 37, 100])
fahrenheit = celsius * 9 / 5 + 32   # scalar broadcasts to every element
print(fahrenheit)
```

Expected output:

```
[ 32.   68.   98.6 212. ]
```

---

## 7. Vectorized aggregations

NumPy computes column-wise or row-wise stats in bulk. The `axis` argument chooses the direction, and it confuses everyone at first.

```python
import numpy as np
m = np.array([[1, 2, 3],
              [4, 5, 6]])
print(m.sum())            # everything -> 21
print(m.sum(axis=0))      # collapse rows -> per-column sums
print(m.sum(axis=1))      # collapse cols -> per-row sums
print(m.mean(axis=0))     # average of each column
```

Expected output:

```
21
[5 7 9]
[ 6 15]
[2.5 3.5 4.5]
```

Mnemonic: `axis=0` means "go down the rows and squash them," leaving one value per column. `axis=1` squashes across columns, leaving one value per row. Get this wrong and you compute the average of the wrong thing - a classic quiet analysis bug.

---

## 8. Random numbers and reproducibility

AI is full of randomness: shuffling data, initializing weights, sampling. Set a **seed** so your results are reproducible - the same "random" numbers every run. A consultant who cannot reproduce a result cannot be trusted.

```python
import numpy as np
rng = np.random.default_rng(seed=42)   # modern seeded generator (PCG64 bit generator)
print(rng.integers(0, 100, size=5))    # 5 random ints in [0, 100)
print(rng.normal(0, 1, size=3).round(3))  # 3 draws from a normal curve
```

Expected output:

```
[ 8 77 65 43 43]
[ 0.941 -1.951 -1.302]
```

Because we seeded with 42, you will get these exact numbers too, as long as the two draws happen in this order from the same generator (the `integers` call advances the generator's state before `normal` runs). Change the seed and everything changes; remove it and every run differs. Always seed before you report a number someone will act on.

`np.random.default_rng` is the recommended modern API (NumPy 1.17+); the older `np.random.seed` / `np.random.rand` global functions still work but are legacy (see: NumPy random generator docs). The default bit generator behind `default_rng` is PCG64, not the old Mersenne Twister.

---

## 9. NaN - the missing-value landmine

`np.nan` ("not a number") represents missing or undefined data. It is contagious: any arithmetic touching a NaN produces NaN, which can silently poison a whole calculation.

```python
import numpy as np
a = np.array([1.0, 2.0, np.nan, 4.0])
print(a.sum())          # nan - one missing value ruins the sum
print(np.nansum(a))     # 7.0 - nan-aware version ignores it
print(np.isnan(a))      # find where the missing values are
```

Expected output:

```
nan
7.0
[False False  True False]
```

When a total comes out as `nan`, you have missing data hiding in the input. Use the `nan`-aware functions (`nansum`, `nanmean`, `nanmax`) or clean the data first. This bites everyone in real datasets, which is the whole subject of Concepts 3.4.

---

## 10. Why this matters for AI

- Every image, every batch of text tokens, every model weight is a NumPy-style array. Shapes are the language you use to reason about them.
- A "dimension mismatch" error at inference time is almost always a shape you did not expect - reading shapes fluently is how you fix it in minutes instead of hours.
- Broadcasting explains both elegant one-liners and baffling silent bugs.
- Vectorization is why AI math is fast enough to be practical. When your analysis is slow, the fix is usually "stop looping, start vectorizing."

You do not need to memorize the whole API. You need to read a shape, spot a broadcast, find a NaN, and know that `axis=0` goes down. That fluency carries you through pandas and every model you will ever touch.

---

## References

- NumPy array creation - https://numpy.org/doc/stable/user/basics.creation.html
- NumPy indexing and broadcasting - https://numpy.org/doc/stable/user/basics.broadcasting.html
- NumPy random Generator (`default_rng`, PCG64) - https://numpy.org/doc/stable/reference/random/generator.html
- NumPy `np.nan` and nan-aware functions (`nansum` etc.) - https://numpy.org/doc/stable/reference/constants.html and https://numpy.org/doc/stable/reference/routines.statistics.html
- Best practices for NumPy random generators - https://blog.scientific-python.org/numpy/numpy-rng/

Outputs in this doc were produced on NumPy 2.3.x (Python 3.12, 64-bit). On 64-bit Linux and macOS the default integer dtype is `int64`; on Windows it is `int32`.
