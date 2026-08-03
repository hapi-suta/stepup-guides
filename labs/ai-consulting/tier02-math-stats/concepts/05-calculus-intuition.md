# Concepts 2.5: Calculus Intuition for AI

**Tier 2 - Mathematics and statistics for AI.** Teaching reference. This is where "how does a model learn?" gets answered. The answer is calculus, but you need almost none of the machinery from a calculus class. You need one idea: **slope tells you which way to move to improve.** Everything else, including training GPT-scale models, is that idea repeated a trillion times.

**Who this is for:** DBAs. No prior calculus assumed. We build on slope from Concepts 2.1.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np`.

---

## 1. Functions, recap

From Concepts 2.1: a function maps input to output, like `f(x) = x**2`. Picture its graph - a U-shaped curve (a parabola). The bottom of the U is the lowest point. A big theme of training AI is: we have a curve that measures "how wrong the model is", and we want to reach the bottom of it.

```python
def f(x):
    return x ** 2

[f(x) for x in [-2, -1, 0, 1, 2]]
```

Expected output:

```
[4, 1, 0, 1, 4]
```

The lowest value is 0, at `x = 0`. That is the bottom of the U.

---

## 2. Derivatives

A **derivative** is the slope of a curve at a single point - how fast the output changes as you nudge the input. For a straight line the slope is the same everywhere. For a curve it changes: steep on the sides, flat at the bottom.

The derivative of `f(x) = x**2` is `2*x` (this is the power rule: the derivative of `x**n` is `n*x**(n-1)` - see: MathWorld Power Rule). You do not need to prove this. Just read what it says:

- At `x = 3`, slope is `6` - steep, going uphill to the right.
- At `x = -3`, slope is `-6` - steep, going uphill to the left.
- At `x = 0`, slope is `0` - flat, the bottom.

You can estimate a derivative numerically by nudging the input a tiny bit and measuring the change (rise over run), which is exactly the slope formula from Concepts 2.1. This is the forward finite-difference approximation of the derivative (see: MathWorld Finite Difference):

```python
def f(x):
    return x ** 2

def slope_at(x, h=1e-6):
    return (f(x + h) - f(x)) / h

print(round(slope_at(3), 4))
print(round(slope_at(0), 4))
```

Expected output (yours will differ slightly):

```
6.0
0.0
```

The slope at 3 is 6; at the bottom it is 0. **A slope of zero means you are at a flat spot.** For a simple bowl-shaped curve like `x**2` that flat spot is the minimum, and that is the signal training uses to know it has arrived. (Strictly, a zero slope marks any flat point - a minimum, a maximum, or a saddle - so in real high-dimensional models a zero gradient is a stationary point, most often a local minimum or saddle rather than the single global bottom. For our bowl there is only one, so it is the minimum - see: MathWorld Stationary Point.)

---

## 3. Gradients

When a function has many inputs (a real model has millions of weights), the slope is not one number - it is one slope per input. That vector of slopes is the **gradient**. It points in the direction of steepest increase. To go **down** (reduce error), you move in the opposite direction: the negative gradient.

Think of standing on a hill in fog. You cannot see the bottom, but you can feel which way is steepest downhill under your feet. Step that way. Repeat. That feeling underfoot is the gradient.

---

## 4. Partial derivatives

A **partial derivative** is the slope with respect to just one input, holding the others fixed. If cost depends on both database count and region price, the partial derivative "with respect to database count" asks: if I add one database and change nothing else, how much does cost move? The gradient is just all the partial derivatives collected into a vector. That is the whole relationship - do not overthink it.

---

## 5. Optimization

**Optimization** means finding the input that makes a function as small (or as large) as possible. In AI we almost always **minimize** something: the error, the loss, the cost. The lowest point of the curve is the goal. Calculus gives us the tool to find it without checking every possible input: follow the slope downhill until it flattens out.

---

## 6. Gradient descent

**Gradient descent** is the algorithm that trains nearly every modern model. The recipe:

1. Start at some guess for the model's parameters.
2. Compute the gradient (the slopes) of the loss at that point.
3. Take a small step in the downhill direction (opposite the gradient). The update rule is `new_param = old_param - learning_rate * gradient` (see: scikit-learn SGD documentation).
4. Repeat until the slope is near zero (the bottom).

Here it is minimizing `f(x) = x**2`, starting from `x = 10`:

```python
def slope_at(x):
    return 2 * x            # derivative of x**2

x = 10.0
learning_rate = 0.1
for step in range(5):
    x = x - learning_rate * slope_at(x)
    print(f"step {step + 1}: x = {x:.4f}")
```

Expected output:

```
step 1: x = 8.0000
step 2: x = 6.4000
step 3: x = 5.1200
step 4: x = 4.0960
step 5: x = 3.2768
```

Each step `x` moves closer to 0, the bottom of the curve. Run more steps and it converges to 0. You will use this exact loop to fit a line in the BUILD lab and watch the loss fall.

---

## 7. Learning rate

The **learning rate** is how big a step you take each iteration. It is the single most important knob in training, and it is a Goldilocks problem:

- **Too small:** you crawl. Training takes forever and may stall before reaching the bottom.
- **Too large:** you overshoot the bottom, bounce to the other side, overshoot again, and can **diverge** - the loss explodes to infinity instead of shrinking.
- **Just right:** steady, quick progress to the bottom.

```python
def slope_at(x):
    return 2 * x

for lr in [0.1, 1.01]:
    x = 10.0
    for _ in range(5):
        x = x - lr * slope_at(x)
    print(f"lr={lr}: final x = {x:.2f}")
```

Expected output:

```
lr=0.1: final x = 3.28
lr=1.01: final x = -11.04
```

With `lr=0.1` we move toward 0. With `lr=1.01` we overshoot and drift **away** from the answer - the first sign of divergence. (Each step multiplies `x` by `1 - lr*2 = -1.02`, a factor whose size is above 1, so the value flips sign and grows every step instead of shrinking.) Diagnosing and fixing a bad learning rate is a SURVIVE scenario in this tier.

---

## 8. Loss functions

A **loss function** measures how wrong the model is on the data: big when predictions are far from the truth, small when they are close. Training = using gradient descent to make the loss small. Two you will meet everywhere:

- **Mean squared error (MSE):** for predicting numbers (regression). Average of the squared differences between prediction and truth (see: scikit-learn mean_squared_error). Squaring punishes big misses hard. You will use MSE in the line-fit BUILD lab.
- **Cross-entropy (log loss):** for predicting categories (classification). Uses the log (Concepts 2.1) so a confident wrong answer is penalized severely. This is the loss behind language models predicting the next word.

```python
import numpy as np
truth       = np.array([3.0, 5.0, 7.0])
predictions = np.array([2.5, 5.5, 6.0])
mse = np.mean((truth - predictions) ** 2)
print("MSE:", round(mse, 4))
```

Expected output:

```
MSE: 0.5
```

The MSE of 0.5 summarizes "how wrong overall" in one number. Gradient descent nudges the model's parameters to drive that number down, step by step, epoch by epoch. That is training. That is all of it.

---

## Key takeaways

- A derivative is the slope of a curve at a point; slope zero = a flat spot = a minimum.
- The gradient is the vector of slopes; the negative gradient points downhill.
- A partial derivative is the slope with respect to one input, holding the rest fixed.
- Gradient descent = repeatedly step downhill until the slope flattens; this trains nearly every model.
- The learning rate is the step size: too small stalls, too large diverges, just right converges.
- A loss function scores how wrong the model is (MSE for numbers, cross-entropy for categories); training minimizes it.

You now have the full toolkit: algebra, linear algebra, probability, statistics, and calculus intuition. Next you put it to work in the BUILD, USE, and SURVIVE labs.

---

## References

- MathWorld, Derivative: https://mathworld.wolfram.com/Derivative.html
- MathWorld, Power Rule (derivative of x^n): https://mathworld.wolfram.com/PowerRule.html
- MathWorld, Finite Difference (numerical derivative): https://mathworld.wolfram.com/FiniteDifference.html
- MathWorld, Stationary Point (zero-slope points): https://mathworld.wolfram.com/StationaryPoint.html
- MathWorld, Gradient: https://mathworld.wolfram.com/Gradient.html
- scikit-learn, Stochastic Gradient Descent (update rule): https://scikit-learn.org/stable/modules/sgd.html
- scikit-learn, mean_squared_error: https://scikit-learn.org/stable/modules/generated/sklearn.metrics.mean_squared_error.html
- scikit-learn, log_loss (cross-entropy): https://scikit-learn.org/stable/modules/generated/sklearn.metrics.log_loss.html
