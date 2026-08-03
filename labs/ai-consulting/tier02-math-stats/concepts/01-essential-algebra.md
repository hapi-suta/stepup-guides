# Concepts 2.1: Essential Algebra for AI

**Tier 2 - Mathematics and statistics for AI.** This is a teaching reference, not a lab. Read it, run the small NumPy snippets on your lab server if you want to see the math move, then come back. You do not need to memorize anything. You need intuition.

**Who this is for:** you are a DBA moving into AI. You already think in tables, sets, and functions (SQL functions, aggregate functions). Algebra is the same idea with different notation. We build every idea up from what you already know and show the Python next to it.

**How to run the snippets:** on your **lab server**, as **ec2-user**, start Python once and paste snippets in:

```bash
python3.12
```

You will see a `>>>` prompt. Type `exit()` to leave.

---

## 1. Variables and functions

A **variable** is a named box that holds a number. In algebra we write `x = 5`. You already do this in SQL (`DECLARE x INT = 5`) and in Python (`x = 5`).

A **function** takes an input, does something, and returns an output. In algebra we write:

```
f(x) = 2x + 1
```

Read that as "f of x equals two x plus one". Give it `x = 3` and it returns `2*3 + 1 = 7`. This is the same as a Python function:

```python
def f(x):
    return 2 * x + 1

f(3)
```

Expected output (yours will differ):

```
7
```

In AI, a whole neural network is just one very large function `f`: you give it an input (a sentence, an image) and it returns an output (a label, the next word). Everything in this tier is about understanding and improving that function.

---

## 2. Linear equations

A **linear equation** draws a straight line:

```
y = m*x + b
```

- `m` is the **slope**: how steep the line is (how much `y` changes when `x` goes up by 1).
- `b` is the **intercept**: where the line crosses the vertical axis (the value of `y` when `x = 0`).

Example: predicting monthly cloud cost from number of databases. If each database costs $40/month and there is a $100 base fee, then `cost = 40*(databases) + 100`. Here `m = 40`, `b = 100`.

```python
def cost(databases):
    return 40 * databases + 100

cost(10)
```

Expected output:

```
500
```

The simplest AI model, linear regression, is exactly this line. Training the model means finding the best `m` and `b` from data. You will do that by hand in the BUILD lab.

---

## 3. Exponents

An **exponent** is repeated multiplication. `2**3` means `2 * 2 * 2 = 8`. In Python the operator is `**`:

```python
2 ** 3
```

Expected output:

```
8
```

Two facts you will meet constantly:

- `x**0 = 1` for any non-zero `x` (the `0**0` case is left undefined/indeterminate, though Python returns `1` for it - see: MathWorld Exponent).
- Negative exponents mean "one over": `2**-1 = 0.5`.

Exponents show up in growth (data doubling every year), in the softmax function that turns raw model scores into probabilities, and in the number of possible values a vector can take.

---

## 4. Logarithms

A **logarithm** is the reverse of an exponent. It answers: "what power do I raise the base to, to get this number?"

`log2(8) = 3` because `2**3 = 8` (a logarithm is the inverse of exponentiation - see: MathWorld Logarithm).

```python
import math
math.log2(8)
```

Expected output:

```
3.0
```

Why logs matter in AI:

- **They compress huge ranges.** A number that goes from 1 to 1,000,000 becomes 0 to 20 in log-base-2. Loss values and probabilities span many orders of magnitude, so we look at them in log scale.
- **Log-loss (cross-entropy)** is the standard loss function for classification. When a model is confident and wrong, the log makes the penalty explode, which is exactly what you want.
- The **natural log** `ln` (base `e`, about 2.71828) is the default in math. In Python `math.log(x)` is the natural log; `math.log(x, base)` takes an explicit base (see: Python math module docs).

```python
math.log(math.e)
```

Expected output:

```
1.0
```

---

## 5. Summation notation

The Greek capital sigma means "add these up". This:

```
sum from i=1 to n of x_i
```

means "add up all the x values from the first to the nth". It is the math version of SQL `SUM(column)` or a Python loop.

```python
import numpy as np
x = np.array([2, 4, 6, 8])
x.sum()
```

Expected output:

```
20
```

Almost every formula in this tier (mean, variance, dot product, loss) is a sum in disguise. When you see sigma, think "SUM over the rows".

---

## 6. Slopes

The **slope** measures rate of change: rise over run. Between two points `(x1, y1)` and `(x2, y2)`:

```
slope = (y2 - y1) / (x2 - x1)
```

Example: cost went from $500 to $700 as databases went from 10 to 15.

```python
(700 - 500) / (15 - 10)
```

Expected output:

```
40.0
```

The slope is $40 per database. Slope is the bridge to calculus (Concepts 2.5): a **derivative** is just the slope of a curve at a single point, and **gradient descent** follows slopes downhill to train a model.

---

## 7. Polynomials

A **polynomial** adds terms with different powers of `x`:

```
f(x) = 3*x**2 + 2*x + 1
```

Straight lines (`degree 1`) are the simplest case. Curves need higher powers. Real data is rarely a perfect straight line, so models add curvature. Too much curvature and the model **overfits**: it memorizes the training data instead of learning the pattern. You will hear "the model is too high-degree" as a way of saying it is too flexible.

```python
def f(x):
    return 3 * x**2 + 2 * x + 1

[f(x) for x in range(4)]
```

Expected output:

```
[1, 6, 17, 34]
```

---

## 8. Probability notation (a first look)

You will meet these symbols in Concepts 2.3. A quick preview so they are not scary:

- `P(A)` means "the probability of event A". It is always between 0 (impossible) and 1 (certain).
- `P(A and B)` means both A and B happen.
- `P(A | B)` means "the probability of A **given** B" - the vertical bar reads as "given". This is conditional probability, the heart of Bayes theorem and of every classifier that outputs "80% chance this is spam".

Example in plain terms: `P(spam | contains the word "free") = 0.7` reads "if an email contains the word free, there is a 70% chance it is spam".

---

## Key takeaways

- A function maps input to output. A neural network is one big function.
- `y = m*x + b` is a line; it is also the simplest AI model.
- Exponents grow, logs shrink and are used in loss functions.
- Sigma means SUM; you already do this in SQL.
- Slope = rate of change = the seed of derivatives and gradient descent.
- `P(A | B)` = probability of A given B; keep this in your pocket for probability.

Next: **Concepts 2.2 - Linear algebra**, where numbers become vectors and matrices, the native language of embeddings and neural networks.

---

## References

- MathWorld, Logarithm (inverse of exponentiation): https://mathworld.wolfram.com/Logarithm.html
- MathWorld, Exponent: https://mathworld.wolfram.com/Exponent.html
- MathWorld, Slope (rise over run): https://mathworld.wolfram.com/Slope.html
- MathWorld, Polynomial: https://mathworld.wolfram.com/Polynomial.html
- Python math module (`math.log` natural log, `math.log2`): https://docs.python.org/3/library/math.html
- numpy.sum (sigma / summation): https://numpy.org/doc/stable/reference/generated/numpy.sum.html
- NIST/SEMATECH e-Handbook, conditional probability (P(A|B)): https://www.itl.nist.gov/div898/handbook/apr/section1/apr131.htm
