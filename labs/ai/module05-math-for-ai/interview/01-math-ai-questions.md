# Interview 01: Math for AI Questions

Five questions you might get in an interview about the math behind AI systems.

---

## Question 1: What is a Dot Product and Why Does AI Care?

**Question:** Explain what a dot product is in simple terms. Then explain why it's the most important operation in AI.

**Strong answer should include:**

**What it is:**
- Multiply matching positions in two vectors, then add up all the results
- `dot([1,2,3], [4,5,6]) = (1*4) + (2*5) + (3*6) = 32`
- In SQL terms: `SELECT SUM(a.value * b.value) FROM a JOIN b ON a.position = b.position`

**Why AI cares (three uses):**

1. **Similarity:** The dot product measures how much two vectors "agree." High value = similar direction = similar meaning. This is how embedding search works (cosine similarity is a normalized dot product).

2. **Neural network layers:** Every layer in a neural network is `output = input @ weights + bias`. The `@` is matrix multiplication, which is just many dot products at once. One dot product per input-output pair.

3. **Attention mechanism:** In transformers (GPT, Claude), the attention score between two tokens is a dot product of their query and key vectors. This is how the model decides which words are related to each other.

**Bonus - hardware connection:** GPUs and tensor cores exist specifically to compute millions of dot products in parallel. When someone says "this model needs an A100 GPU," they mean "it needs to compute dot products very fast."

---

## Question 2: Why Do We Normalize Data Before Training?

**Question:** A junior engineer feeds raw server metrics (CPU 0-100, Memory 0-16384MB, Connections 0-300) directly into a model. What goes wrong and how do you fix it?

**Strong answer should include:**

**What goes wrong:**
- Features on larger scales (Memory: 0-16384) dominate features on smaller scales (CPU: 0-100)
- Distance calculations are almost entirely determined by Memory differences
- Gradient descent takes a zigzag path (fast along large-scale features, slow along small-scale ones)
- The model may ignore small-scale features entirely

**How to fix it (two methods):**

1. **Min-Max normalization:** Scale everything to 0-1
   - `normalized = (value - min) / (max - min)`
   - Good when you know the absolute range

2. **Z-score (standardization):** Scale to mean=0, std=1
   - `normalized = (value - mean) / std`
   - Good when you don't know the range
   - Most common in practice

**Critical production detail:**
- Save `mean` and `std` from training data
- Apply the SAME normalization at prediction time
- If you normalize training data but not prediction data, the model produces garbage
- This is one of the most common production ML bugs

---

## Question 3: Explain Gradient Descent Like I'm Not a Math Person

**Question:** How does a model learn? Explain gradient descent without using any formulas.

**Strong answer:**

Imagine you're blindfolded in a hilly landscape and you need to find the lowest point (a valley). You can feel the ground under your feet.

1. **Feel the slope:** Which direction goes downhill? That's the gradient - it tells you which direction makes things better (reduces the error).

2. **Take a step:** Walk downhill. How big a step? That's the learning rate.

3. **Repeat:** Feel the slope again, take another step. Keep going until the ground feels flat (you're at the bottom).

**DBA analogy:** It's like auto-tuning `shared_buffers`:
- Try a value, measure query performance (loss)
- Increase or decrease based on whether performance improved (gradient)
- Adjust by a reasonable amount (learning rate)
- Repeat until performance stabilizes

**Three things that go wrong:**
1. **Learning rate too high:** You take huge steps and jump over the valley, bouncing back and forth, never settling (gradient explosion)
2. **Learning rate too low:** You take tiny steps and it takes 10,000 iterations to reach the valley (slow convergence)
3. **Local minimum:** You find a small dip but there's a deeper valley nearby. You stop too early because the ground feels flat locally.

**What the model actually adjusts:** The weights in each layer. Millions or billions of numbers, each adjusted a tiny bit each step, all in the direction that reduces the prediction error.

---

## Question 4: What's the Difference Between a Vector, a Matrix, and a Tensor?

**Question:** Explain vectors, matrices, and tensors with a database analogy.

**Strong answer:**

| Math Term | Dimensions | DBA Analogy | AI Example |
|-----------|-----------|-------------|------------|
| Scalar | 0D (one number) | A single cell value | Loss = 0.34 |
| Vector | 1D (list of numbers) | One row from a query | Embedding [0.1, -0.3, 0.8, ...] |
| Matrix | 2D (table of numbers) | A query result set | Weight matrix in a neural network layer |
| Tensor | 3D+ (stack of tables) | Multiple result sets | Batch of images, sequence of embeddings |

**Concrete examples:**
- **Scalar:** `SELECT count(*) FROM users;` - one number (42)
- **Vector:** `SELECT cpu, memory, disk FROM server_metrics WHERE id=1;` - [92.5, 68.3, 45.1]
- **Matrix:** `SELECT cpu, memory, disk FROM server_metrics;` - 100 rows x 3 columns
- **Tensor:** The same query result for 30 days - 30 x 100 x 3 (days x servers x metrics)

**Why tensors matter:** Real AI data has many dimensions:
- Text: (batch_size, sequence_length, embedding_dim) - 3D tensor
- Images: (batch_size, height, width, channels) - 4D tensor
- Video: (batch_size, frames, height, width, channels) - 5D tensor

PyTorch and TensorFlow are named after tensors because that's the data structure everything runs on.

---

## Question 5: A Model Gets 95% Accuracy But Fails in Production. What Went Wrong?

**Question:** Your team trained a server health classifier with 95% accuracy on test data. In production, it misses most real incidents. Use statistics to explain what might have happened.

**Strong answer should include:**

**Most likely cause: class imbalance.**

If 95% of servers are healthy and 5% have incidents, a model that ALWAYS predicts "healthy" gets 95% accuracy while catching zero incidents.

**Statistics to check:**

1. **Confusion matrix:** Break accuracy into true positives, false positives, true negatives, false negatives
   - 95% accuracy might be: 950 correct "healthy" + 0 correct "incident" out of 1000

2. **Precision and recall:**
   - Precision: "When the model says 'incident,' how often is it right?"
   - Recall: "Of all real incidents, how many did the model catch?"
   - A model that never predicts "incident" has 0% recall

3. **Class distribution:** Check if training data matched production
   - Training: 50/50 healthy/sick (balanced)
   - Production: 95/5 healthy/sick (imbalanced)
   - The model never learned to recognize the rare class at scale

**Fixes:**
- Use balanced metrics (F1 score, AUC-ROC) instead of accuracy
- Oversample the rare class or undersample the common class
- Weight the loss function (penalize missing incidents more)
- Set a lower threshold (predict "incident" if probability > 0.3 instead of > 0.5)

**DBA analogy:** It's like monitoring that only alerts on average query time. If 95% of queries are fast and 5% are 10-second table scans, the average looks fine. You need to look at p95/p99, not just the mean.
