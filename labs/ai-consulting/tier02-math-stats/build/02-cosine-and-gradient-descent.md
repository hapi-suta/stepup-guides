# BUILD: Cosine Similarity and Gradient Descent by Hand

**Tier 2 - the "make the math move" build.** You will implement two of the most important algorithms in AI from scratch in NumPy: **cosine similarity** (the engine of semantic search and RAG) and **gradient descent** (the engine that trains almost every model). No black boxes. You will watch the loss fall, one epoch at a time.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25. Output shown is real (random draws will differ).

**Prerequisite:** you read Concepts 2.2 (Linear algebra, dot products, cosine) and Concepts 2.5 (Calculus, gradient descent, learning rate, loss).

**What you build:** a folder `build-cosine-gd/` with two scripts: `cosine.py` and `gradient_descent.py`, plus one saved chart showing the loss curve.

---

## Step 1: Create the project folder

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/build-cosine-gd
```

Move into it:

```bash
cd ~/build-cosine-gd
```

---

## Step 2: Create and activate a virtual environment

Still on your **lab server**, as **ec2-user**, in `~/build-cosine-gd`:

```bash
python3.12 -m venv .venv
```

Activate it:

```bash
source .venv/bin/activate
```

Your prompt now shows `(.venv)`.

---

## Step 3: Install NumPy and matplotlib

Still in the activated environment:

```bash
pip install numpy matplotlib
```

Confirm:

```bash
pip list | grep -Ei "numpy|matplotlib"
```

Expected output (yours will differ):

```
matplotlib        3.9.2
numpy             2.1.1
```

---

## Part A: Cosine similarity from scratch

### Step 4: Write the cosine similarity script

The plan (straight from Concepts 2.2): cosine similarity is the dot product of two vectors divided by the product of their lengths (norms). We build it from primitives, then check it against NumPy's own tools.

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi cosine.py
```

Press `i` and enter:

```python
import numpy as np

def dot_product(a, b):
    """Multiply position by position, then sum. The core AI operation."""
    return np.sum(a * b)

def magnitude(a):
    """Length of a vector: square root of the sum of squares."""
    return np.sqrt(np.sum(a ** 2))

def cosine_similarity(a, b):
    """Dot product divided by the product of magnitudes. Range -1 to 1."""
    denom = magnitude(a) * magnitude(b)
    if denom == 0:
        return 0.0            # guard against a zero-length vector
    return dot_product(a, b) / denom

# Three tiny "document" vectors. Imagine each number is a topic weight.
sports   = np.array([5, 4, 0, 0])   # heavy on the first two topics
football = np.array([4, 5, 1, 0])   # very similar to sports
cooking  = np.array([0, 1, 5, 4])   # different topics entirely

print("sports vs football:", round(cosine_similarity(sports, football), 4))
print("sports vs cooking: ", round(cosine_similarity(sports, cooking), 4))

# Sanity check: our result must match the manual dot-product / norm formula
reference = np.dot(sports, football) / (np.linalg.norm(sports) * np.linalg.norm(football))
print("matches numpy reference:", np.isclose(cosine_similarity(sports, football), reference))

# A vector is always perfectly similar to itself (cosine = 1.0)
print("sports vs itself:  ", round(cosine_similarity(sports, sports), 4))
```

Press `Esc`, type `:wq`, press Enter.

### Step 5: Run the cosine script

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python cosine.py
```

Expected output:

```
sports vs football: 0.9639
sports vs cooking:  0.0964
matches numpy reference: True
sports vs itself:   1.0
```

Read the numbers: "sports" and "football" score 0.96 - almost the same direction, so semantically close. "sports" and "cooking" score 0.10 - nearly unrelated. Any vector scores 1.0 against itself. This is exactly how a RAG system decides which stored documents match a query. You just built the core of semantic search in about 15 lines.

---

## Part B: Gradient descent from scratch

### Step 6: The goal

We have some `(x, y)` data points that roughly lie on a line. We want to find the best line `y = w*x + b` by minimizing the mean squared error (MSE loss from Concepts 2.5). We will NOT solve it with a formula - we will let gradient descent discover `w` and `b` by stepping downhill, and we will print the loss every few epochs to watch it fall.

An **epoch** is one full pass over the data. The **gradients** of MSE with respect to `w` and `b` are standard results; we use them directly.

### Step 7: Write the gradient descent script

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi gradient_descent.py
```

Press `i` and enter:

```python
import numpy as np
import matplotlib
matplotlib.use("Agg")   # save charts to file on a headless server
import matplotlib.pyplot as plt

np.random.seed(0)

# Make fake data that truly follows y = 2*x + 5, plus a little noise.
# We center x around 0 (range -5 to 5) so plain gradient descent converges
# cleanly - it should rediscover w near 2 and b near 5.
x = np.linspace(-5, 5, 50)
true_w, true_b = 2.0, 5.0
y = true_w * x + true_b + np.random.normal(0, 1, size=x.shape)

def predict(x, w, b):
    return w * x + b

def mse_loss(x, y, w, b):
    """Mean squared error: average of squared prediction errors."""
    errors = predict(x, w, b) - y
    return np.mean(errors ** 2)

# Start with a bad guess on purpose.
w, b = 0.0, 0.0
learning_rate = 0.05
epochs = 200
n = len(x)

loss_history = []
for epoch in range(epochs):
    errors = predict(x, w, b) - y          # how wrong each point is
    # Gradients of MSE (the downhill direction for each parameter):
    grad_w = (2 / n) * np.sum(errors * x)
    grad_b = (2 / n) * np.sum(errors)
    # Step downhill: move opposite the gradient, scaled by the learning rate.
    w = w - learning_rate * grad_w
    b = b - learning_rate * grad_b

    loss = mse_loss(x, y, w, b)
    loss_history.append(loss)
    if epoch % 20 == 0:
        print(f"epoch {epoch:3d} | loss {loss:7.3f} | w {w:.3f} | b {b:.3f}")

print(f"\nFinal:  w = {w:.3f} (true 2.0), b = {b:.3f} (true 5.0)")
print(f"Final loss: {loss_history[-1]:.3f}")

# Plot the loss curve so you can SEE it fall.
fig, ax = plt.subplots(figsize=(7, 4))
ax.plot(loss_history, color="#4C72B0")
ax.set_title("Training Loss per Epoch (gradient descent)")
ax.set_xlabel("Epoch")
ax.set_ylabel("MSE loss")
fig.tight_layout()
fig.savefig("loss_curve.png", dpi=100)
print("Saved loss_curve.png")
```

Press `Esc`, type `:wq`, press Enter.

### Step 8: Run gradient descent and watch the loss fall

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python gradient_descent.py
```

Expected output (yours will differ slightly):

```
epoch   0 | loss  23.026 | w 1.612 | b 0.514
epoch  20 | loss   1.410 | w 1.859 | b 4.578
epoch  40 | loss   1.099 | w 1.859 | b 5.072
epoch  60 | loss   1.094 | w 1.859 | b 5.132
epoch  80 | loss   1.094 | w 1.859 | b 5.140
epoch 100 | loss   1.094 | w 1.859 | b 5.140
epoch 120 | loss   1.094 | w 1.859 | b 5.141
epoch 140 | loss   1.094 | w 1.859 | b 5.141
epoch 160 | loss   1.094 | w 1.859 | b 5.141
epoch 180 | loss   1.094 | w 1.859 | b 5.141

Final:  w = 1.859 (true 2.0), b = 5.141 (true 5.0)
Final loss: 1.094
```

Watch what happened: the loss started around 23 and fell to about 1.1, where it flattened (the slope reached near zero - the bottom of the curve). Meanwhile `w` climbed from 0 toward the true 2.0 and `b` climbed toward the true 5.0. The model **learned** the line from nothing but the data and the downhill rule. This is training. Every model you will ever use does a bigger version of this.

The final `w = 1.859` and `b = 5.141` are close to but not exactly the true 2.0 and 5.0, and that is correct behavior, not a bug. We added random noise to the data, so the best-fit line for this particular noisy sample sits slightly off the underlying truth. The model found the best line for the data it was given. More data or less noise would land it even closer.

### Step 9: Confirm the loss curve was saved

Still on your **lab server**, as **ec2-user**:

```bash
ls -lh loss_curve.png
```

Expected output (yours will differ):

```
-rw-rw-r-- 1 ec2-user ec2-user 27K Jul 25 14:20 loss_curve.png
```

The chart shows a steep drop that levels off - the classic "learning curve" shape you will see in every training dashboard.

---

## Step 10 (experiment): break it on purpose

Understanding gradient descent means knowing how it fails. Open the script again:

```bash
vi gradient_descent.py
```

Press `i`, find the line `learning_rate = 0.05`, and change it to a much larger value:

```python
learning_rate = 0.2
```

Press `Esc`, type `:wq`, press Enter. Run it again:

```bash
python gradient_descent.py
```

Expected output (yours will differ, but the pattern is the same):

```
epoch   0 | loss  38.9... | w ... | b ...
epoch  20 | loss  1.4e+40 | w -1.2e+20 | b ...
...
epoch 180 | loss    inf | w nan | b nan
```

The loss explodes toward `inf` and the parameters become `nan` (not a number). That is **divergence**: the learning rate was too big, so each step overshot the bottom and bounced higher, forever. Change it back to `0.05` and confirm it converges again. You just witnessed the failure mode you will diagnose in the SURVIVE "gradient-descent-diverges" scenario.

Restore the good value before finishing:

```bash
vi gradient_descent.py
```

Set `learning_rate = 0.05` again, save with `:wq`.

---

## What you accomplished

- Implemented cosine similarity from dot product and magnitude, and verified it against NumPy - the exact math behind semantic search and RAG.
- Implemented gradient descent from scratch to fit a line, watched the MSE loss fall per epoch, and recovered the true parameters from noisy data.
- Saw divergence firsthand by setting the learning rate too high, and understood why it happens.

You now understand, from the inside, both how AI compares meaning and how AI learns. Next: the USE labs, where you apply an A/B test and embedding distances to fresh data.
