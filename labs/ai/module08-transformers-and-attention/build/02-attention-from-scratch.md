# Build 02: Attention from Scratch

This is the core of the Transformer. You'll build the attention mechanism step by step - from raw math to a working implementation. Every line is explained.

---

## Step 1. The intuition - what attention does

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
What is attention?

Sentence: "The server crashed because it ran out of memory"

When the model processes the word "it", it needs to know
what "it" refers to. Attention creates a score between
"it" and EVERY other word:

  "it" <-> "The"      = 0.02  (low - not relevant)
  "it" <-> "server"   = 0.71  (HIGH - "it" refers to "server")
  "it" <-> "crashed"  = 0.08  (some relevance)
  "it" <-> "because"  = 0.03  (low)
  "it" <-> "ran"      = 0.05  (low)
  "it" <-> "out"      = 0.02  (low)
  "it" <-> "of"       = 0.01  (low)
  "it" <-> "memory"   = 0.08  (some relevance)

These scores add up to 1.0 (it's a probability distribution).
The model uses these scores to create a weighted combination
of all word meanings - heavily weighted toward "server".

DBA analogy:
  Without attention: SELECT * FROM words ORDER BY position
  (reads words in order, like a sequential scan)

  With attention: SELECT * FROM words ORDER BY relevance_to('it')
  (jumps to the most relevant words, like an indexed lookup)
""")
PYEOF
```

---

## Step 2. Query, Key, Value - the three pieces

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
Attention uses three projections of each word:

  Query (Q): "What am I looking for?"
  Key (K):   "What do I contain?"
  Value (V): "What information do I carry?"

DBA analogy:
  Query = the WHERE clause (what you're searching for)
  Key   = the indexed column (what gets matched against)
  Value = the SELECT columns (what you actually return)

  SELECT value FROM words WHERE key MATCHES query

The "match" is a dot product between Q and K.
High dot product = high relevance = this word matters.
""")

torch.manual_seed(42)

# Simulate 4 words, each represented by a 8-dimensional embedding
seq_len = 4       # 4 words in our sentence
d_model = 8       # each word is an 8-dim vector (real models use 768)

# Random embeddings for our 4 words
X = torch.randn(seq_len, d_model)
# shape: [4, 8] = 4 words, each with 8 numbers
print(f"Input X shape: {X.shape}")
print(f"Think of this as: 4 words, each represented by 8 numbers")
print()

# Create Q, K, V by multiplying input by weight matrices
# These weight matrices are LEARNED during training
W_Q = nn.Linear(d_model, d_model, bias=False)  # 8 -> 8
W_K = nn.Linear(d_model, d_model, bias=False)  # 8 -> 8
W_V = nn.Linear(d_model, d_model, bias=False)  # 8 -> 8
# bias=False is common in attention (simplifies the math slightly)

Q = W_Q(X)  # Query: what each word is looking for
K = W_K(X)  # Key: what each word offers to be found
V = W_V(X)  # Value: the actual information each word carries

print(f"Q shape: {Q.shape}  (each word has a query vector)")
print(f"K shape: {K.shape}  (each word has a key vector)")
print(f"V shape: {V.shape}  (each word has a value vector)")
print()
print("Q, K, V are different 'views' of the same input")
print("The model LEARNS the best W_Q, W_K, W_V during training")
PYEOF
```

Expected output (yours will differ):

```
Input X shape: torch.Size([4, 8])
Think of this as: 4 words, each represented by 8 numbers

Q shape: torch.Size([4, 8])  (each word has a query vector)
K shape: torch.Size([4, 8])  (each word has a key vector)
V shape: torch.Size([4, 8])  (each word has a value vector)
```

---

## Step 3. Computing attention scores

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.nn.functional as F  # F contains functions like softmax

torch.manual_seed(42)

# Setup: 4 words, 8-dim embeddings
seq_len = 4
d_model = 8

X = torch.randn(seq_len, d_model)
W_Q = nn.Linear(d_model, d_model, bias=False)
W_K = nn.Linear(d_model, d_model, bias=False)
W_V = nn.Linear(d_model, d_model, bias=False)

Q = W_Q(X)
K = W_K(X)
V = W_V(X)

# STEP 1: Compute attention scores (Q * K^T)
# Each query asks: "how relevant is each key to me?"
scores = Q @ K.transpose(-2, -1)
# Q shape: [4, 8], K^T shape: [8, 4]
# Result: [4, 4] - score between every pair of words
# K.transpose(-2, -1) swaps the last two dimensions (rows <-> columns)

print("Step 1: Raw attention scores (Q @ K^T)")
print(f"Shape: {scores.shape} (4 words x 4 words = every pair)")
print(scores)
print()

# STEP 2: Scale the scores
# Without scaling, scores get too large for softmax to work well
# Divide by sqrt(d_model) to keep values in a reasonable range
d_k = d_model  # dimension of keys
scores_scaled = scores / (d_k ** 0.5)
# d_k ** 0.5 is the square root of d_k
# For d_k=8, that's sqrt(8) = 2.83
# This prevents softmax from producing values very close to 0 or 1

print(f"Step 2: Scaled scores (divided by sqrt({d_k}) = {d_k**0.5:.2f})")
print(scores_scaled)
print()

# STEP 3: Apply softmax to get probabilities
# softmax converts raw scores to probabilities (0 to 1, sums to 1)
attention_weights = F.softmax(scores_scaled, dim=-1)
# dim=-1 means apply softmax across the last dimension (columns)
# Each ROW sums to 1.0

print("Step 3: Attention weights (after softmax)")
print(attention_weights)
print()

# Verify each row sums to 1
row_sums = attention_weights.sum(dim=-1)
print(f"Row sums: {row_sums}")
print("Each word's attention over all other words sums to 1.0")
print()

# STEP 4: Multiply by Values to get the output
# Each word's output = weighted sum of all Value vectors
output = attention_weights @ V
# attention_weights: [4, 4], V: [4, 8]
# Result: [4, 8] - 4 words, each now a mix of all word values

print(f"Step 4: Output (attention_weights @ V)")
print(f"Shape: {output.shape}")
print()
print("Each word is now a WEIGHTED COMBINATION of all word values")
print("Words that had high attention weights contribute more")
PYEOF
```

Expected output (yours will differ):

```
Step 1: Raw attention scores (Q @ K^T)
Shape: torch.Size([4, 4]) (4 words x 4 words = every pair)
tensor([[ 0.52, -0.31,  0.18,  0.44],
        [-0.12,  0.67, -0.23,  0.11],
        ...])

Step 2: Scaled scores (divided by sqrt(8) = 2.83)
...

Step 3: Attention weights (after softmax)
tensor([[0.31, 0.18, 0.22, 0.29],
        [0.21, 0.38, 0.17, 0.24],
        ...])

Row sums: tensor([1.0000, 1.0000, 1.0000, 1.0000])
```

---

## Step 4. Put it all together - the attention function

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.nn.functional as F

def scaled_dot_product_attention(Q, K, V):
    """
    The complete attention mechanism in one function.

    Q: Query tensor [seq_len, d_k]
    K: Key tensor   [seq_len, d_k]
    V: Value tensor  [seq_len, d_v]

    Returns: output [seq_len, d_v], attention_weights [seq_len, seq_len]
    """
    d_k = Q.shape[-1]              # dimension of keys (last dimension of Q)
    scores = Q @ K.transpose(-2, -1)  # [seq_len, seq_len]
    scores = scores / (d_k ** 0.5)    # scale by sqrt(d_k)
    weights = F.softmax(scores, dim=-1)  # convert to probabilities
    output = weights @ V               # weighted sum of values
    return output, weights

# Test it
torch.manual_seed(42)
d_model = 8
seq_len = 4

X = torch.randn(seq_len, d_model)
W_Q = nn.Linear(d_model, d_model, bias=False)
W_K = nn.Linear(d_model, d_model, bias=False)
W_V = nn.Linear(d_model, d_model, bias=False)

Q, K, V = W_Q(X), W_K(X), W_V(X)

output, weights = scaled_dot_product_attention(Q, K, V)

print("Scaled Dot-Product Attention")
print(f"  Input:   {seq_len} words, {d_model}-dim embeddings")
print(f"  Output:  {output.shape} (same shape as input)")
print(f"  Weights: {weights.shape} (attention matrix)")
print()

# Visualize attention as a text grid
words = ["The", "server", "is", "slow"]
print("Attention weights (which word pays attention to which):")
print(f"{'':>10s}", end="")
for w in words:
    print(f"{w:>8s}", end="")
print()

for i, w in enumerate(words):
    print(f"{w:>10s}", end="")
    for j in range(len(words)):
        val = weights[i, j].item()
        print(f"{val:>8.3f}", end="")
    print()

print()
print("Read each ROW: 'The' pays 0.XXX attention to 'The', 0.XXX to 'server', etc.")
print("High values = strong attention = 'this word is important to me'")
PYEOF
```

Expected output (yours will differ):

```
Scaled Dot-Product Attention
  Input:   4 words, 8-dim embeddings
  Output:  torch.Size([4, 8]) (same shape as input)
  Weights: torch.Size([4, 4]) (attention matrix)

Attention weights (which word pays attention to which):
               The  server      is    slow
       The   0.312   0.178   0.221   0.289
    server   0.210   0.381   0.172   0.237
        is   0.265   0.198   0.301   0.236
      slow   0.229   0.287   0.198   0.286
```

---

## Step 5. Multi-head attention

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.nn.functional as F

print("""
Multi-Head Attention: run attention MULTIPLE TIMES in parallel.

Why? One attention head might learn:
  - Head 1: grammar (subject-verb agreement)
  - Head 2: meaning (what "it" refers to)
  - Head 3: position (nearby words matter more)
  - Head 4: domain (database-related words cluster)

Each head looks at the data differently.

DBA analogy: Like having multiple indexes on a table.
  - B-tree index: good for range queries
  - Hash index: good for equality
  - GIN index: good for full-text search
  Each reveals different patterns. Multi-head attention
  does the same thing with word relationships.
""")

# === PYTHON CLASSES - WHAT YOU NEED TO KNOW ===
# A class is a blueprint for creating objects. Like CREATE TYPE in PostgreSQL.
#
# class MultiHeadAttention(nn.Module):
#   ^                      ^
#   |                      +-- inherits from nn.Module (gets PyTorch features for free)
#   +-- the name of our blueprint
#
# def __init__(self, ...):  <- runs when you create one (like DEFAULT values on a table)
# self.something = ...      <- "self" refers to THIS instance (like NEW in a trigger)
# super().__init__()        <- initialize the parent class (nn.Module) first
#                              like calling a parent constructor before adding your own setup

class MultiHeadAttention(nn.Module):
    """Multi-head attention from scratch."""

    def __init__(self, d_model, num_heads):
        super().__init__()
        # super().__init__() initializes the nn.Module base class (required)

        self.num_heads = num_heads       # how many parallel attention heads
        self.d_model = d_model           # total embedding dimension
        self.d_k = d_model // num_heads  # dimension per head
        # Example: d_model=8, num_heads=2 -> each head works with 4 dims

        # One big linear layer, then we split it into heads
        self.W_Q = nn.Linear(d_model, d_model, bias=False)
        self.W_K = nn.Linear(d_model, d_model, bias=False)
        self.W_V = nn.Linear(d_model, d_model, bias=False)
        self.W_O = nn.Linear(d_model, d_model, bias=False)
        # W_O combines all heads back into one output

    def forward(self, X):
        batch_size = X.shape[0] if X.dim() == 3 else 1
        # X.dim() returns number of dimensions
        # If X is 2D [seq_len, d_model], treat batch_size as 1
        if X.dim() == 2:
            X = X.unsqueeze(0)  # add batch dimension: [seq_len, d_model] -> [1, seq_len, d_model]
        seq_len = X.shape[1]

        # Project to Q, K, V
        Q = self.W_Q(X)  # [batch, seq_len, d_model]
        K = self.W_K(X)
        V = self.W_V(X)

        # Split into multiple heads
        # Reshape: [batch, seq_len, d_model] -> [batch, seq_len, num_heads, d_k]
        Q = Q.view(batch_size, seq_len, self.num_heads, self.d_k)
        K = K.view(batch_size, seq_len, self.num_heads, self.d_k)
        V = V.view(batch_size, seq_len, self.num_heads, self.d_k)
        # .view() reshapes without copying data

        # Transpose to: [batch, num_heads, seq_len, d_k]
        # This puts each head's data together for parallel processing
        Q = Q.transpose(1, 2)
        K = K.transpose(1, 2)
        V = V.transpose(1, 2)

        # Attention for all heads at once
        scores = Q @ K.transpose(-2, -1) / (self.d_k ** 0.5)
        weights = F.softmax(scores, dim=-1)
        attended = weights @ V
        # weights shape: [batch, num_heads, seq_len, seq_len]
        # attended shape: [batch, num_heads, seq_len, d_k]

        # Concatenate heads back together
        attended = attended.transpose(1, 2)  # [batch, seq_len, num_heads, d_k]
        attended = attended.contiguous().view(batch_size, seq_len, self.d_model)
        # .contiguous() ensures memory is laid out correctly for .view()
        # .view() merges num_heads and d_k back to d_model

        # Final projection
        output = self.W_O(attended)

        return output, weights

# Test it
torch.manual_seed(42)
d_model = 8
num_heads = 2
seq_len = 4

X = torch.randn(seq_len, d_model)  # 4 words, 8-dim each
mha = MultiHeadAttention(d_model, num_heads)

output, weights = mha(X)

print(f"Input shape:  {X.shape}")
print(f"Output shape: {output.squeeze(0).shape} (same as input!)")
print(f"Weights shape: {weights.shape}")
print(f"  = [batch={weights.shape[0]}, heads={weights.shape[1]}, "
      f"seq={weights.shape[2]}, seq={weights.shape[3]}]")
print()

# Show each head's attention pattern
words = ["The", "server", "is", "slow"]
for h in range(num_heads):
    print(f"Head {h+1} attention:")
    for i, w in enumerate(words):
        attn = [f"{weights[0, h, i, j].item():.2f}" for j in range(seq_len)]
        # weights[0, h, i, j]: batch 0, head h, word i attending to word j
        print(f"  {w:>8s} -> {attn}")
    print()

print("Each head learned a DIFFERENT attention pattern")
print("The model combines all heads to make its final decision")
PYEOF
```

Expected output (yours will differ):

```
Input shape:  torch.Size([4, 8])
Output shape: torch.Size([4, 8]) (same as input!)
Weights shape: torch.Size([1, 2, 4, 4])

Head 1 attention:
       The -> ['0.31', '0.22', '0.25', '0.22']
    server -> ['0.18', '0.41', '0.20', '0.21']
        is -> ['0.27', '0.19', '0.32', '0.22']
      slow -> ['0.24', '0.30', '0.21', '0.25']

Head 2 attention:
       The -> ['0.28', '0.19', '0.24', '0.29']
    server -> ['0.23', '0.35', '0.18', '0.24']
        is -> ['0.26', '0.21', '0.28', '0.25']
      slow -> ['0.22', '0.25', '0.22', '0.31']

Each head learned a DIFFERENT attention pattern
The model combines all heads to make its final decision
```

---

## Step 6. PyTorch's built-in attention

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
Good news: you don't have to build attention from scratch in practice.
PyTorch provides nn.MultiheadAttention that does everything we just built.

But now you UNDERSTAND what it does inside:
  1. Project input to Q, K, V
  2. Split into multiple heads
  3. Compute scaled dot-product attention per head
  4. Concatenate heads and project output
""")

torch.manual_seed(42)
d_model = 8
num_heads = 2
seq_len = 4

X = torch.randn(seq_len, d_model)

# PyTorch's built-in MultiheadAttention
mha = nn.MultiheadAttention(
    embed_dim=d_model,   # total embedding dimension
    num_heads=num_heads,  # number of attention heads
    batch_first=False,    # PyTorch MHA expects [seq_len, batch, d_model] by default
)

# PyTorch MHA takes (query, key, value) separately
# For self-attention, all three are the same input
X_batched = X.unsqueeze(1)  # add batch dim: [seq_len, 1, d_model]

output, attention_weights = mha(X_batched, X_batched, X_batched)
# Returns: output [seq_len, batch, d_model], weights [batch, seq_len, seq_len]

print(f"Input shape:   {X.shape}")
print(f"Output shape:  {output.squeeze(1).shape}")
print(f"Weights shape: {attention_weights.shape}")
print()
print("PyTorch's nn.MultiheadAttention does the same thing as our")
print("hand-built version, but optimized for speed.")
print()
print("In practice, you'll ALWAYS use nn.MultiheadAttention.")
print("But now you know exactly what's happening inside.")
PYEOF
```

---

## What You Learned

| Concept | What It Does | Formula |
|---------|-------------|---------|
| Query (Q) | "What am I looking for?" | Q = X @ W_Q |
| Key (K) | "What do I contain?" | K = X @ W_K |
| Value (V) | "What information do I carry?" | V = X @ W_V |
| Attention scores | How relevant is each word to each other word | scores = Q @ K^T |
| Scaling | Prevent scores from getting too large | scores / sqrt(d_k) |
| Softmax | Convert scores to probabilities (sum to 1) | weights = softmax(scores) |
| Output | Weighted mix of all values | output = weights @ V |
| Multi-head | Multiple parallel attention patterns | Split, attend, concatenate |

**The attention formula in one line:**
```
Attention(Q, K, V) = softmax(Q @ K^T / sqrt(d_k)) @ V
```

This is the most important equation in modern AI.
