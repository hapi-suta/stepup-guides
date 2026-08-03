# Build 03: The Transformer Block

Now you know tokenization (Build 01) and attention (Build 02). This guide assembles them into a complete Transformer block - the building block that gets stacked to create BERT, GPT, Claude, and every other LLM.

---

## Step 1. The components of a Transformer block

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
A Transformer block has 4 components:

  Input (word embeddings)
    |
    v
  [1] Multi-Head Attention
    |--- What we built in Build 02
    |--- "Which words should I pay attention to?"
    |
    v
  [2] Add & Layer Norm (residual connection)
    |--- output = LayerNorm(input + attention_output)
    |--- The "add" is a skip connection (Module 07 mentioned these)
    |--- Prevents vanishing gradients in deep networks
    |
    v
  [3] Feed-Forward Network (FFN)
    |--- Two linear layers with ReLU/GELU between them
    |--- Processes each word INDEPENDENTLY
    |--- "Now that I know what to focus on, compute something useful"
    |
    v
  [4] Add & Layer Norm (another residual connection)
    |--- output = LayerNorm(ffn_input + ffn_output)
    |
    v
  Output (enriched word embeddings)

DBA analogy:
  [1] Attention = JOIN (find related data)
  [2] Add & Norm = checkpoint (save intermediate results)
  [3] FFN = WHERE + CASE (compute/transform each row)
  [4] Add & Norm = another checkpoint

Stack 12 of these blocks = BERT
Stack 96 of these blocks = GPT-3
""")
PYEOF
```

---

## Step 2. Layer Normalization

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
Layer Normalization: normalize each sample to mean=0, std=1.

Why? Without normalization, values can grow very large or very
small as they pass through many layers. LayerNorm keeps them
in a stable range.

DBA analogy: Like StandardScaler from Module 06, but applied
INSIDE the model at every layer, not just to the input data.
""")

torch.manual_seed(42)

# Simulate 4 words with 8-dim embeddings
X = torch.randn(4, 8) * 10  # multiply by 10 to make values larger
# * 10 exaggerates the scale so you can see the effect of normalization

print("Before LayerNorm:")
print(f"  Mean per word:  {X.mean(dim=-1).tolist()}")
# .mean(dim=-1) computes mean across the last dimension (the 8 features)
# .tolist() converts tensor to Python list for cleaner printing
print(f"  Std per word:   {X.std(dim=-1).tolist()}")
print()

# Apply LayerNorm
layer_norm = nn.LayerNorm(8)  # normalize across 8 features
# nn.LayerNorm(8) creates a normalizer for 8-dimensional vectors
# It has learnable scale and shift parameters (gamma and beta)

X_normed = layer_norm(X)

print("After LayerNorm:")
print(f"  Mean per word:  {[round(x, 4) for x in X_normed.mean(dim=-1).tolist()]}")
# list comprehension: round each value to 4 decimal places
print(f"  Std per word:   {[round(x, 4) for x in X_normed.std(dim=-1, unbiased=False).tolist()]}")
# unbiased=False divides by N instead of N-1 (matches LayerNorm's formula)
print()
print("Each word's embedding now has mean near 0 and std near 1")
print("This makes training stable even with 96 stacked blocks")
PYEOF
```

Expected output (yours will differ):

```
Before LayerNorm:
  Mean per word:  [1.23, -3.45, 2.67, -0.89]
  Std per word:   [8.12, 9.34, 7.56, 10.23]

After LayerNorm:
  Mean per word:  [0.0, 0.0, 0.0, 0.0]
  Std per word:   [1.0, 1.0, 1.0, 1.0]
```

---

## Step 3. Residual connections (skip connections)

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
Residual Connection: add the input back to the output.

  output = LayerNorm(input + sublayer(input))

Instead of: output = sublayer(input)
We do:      output = input + sublayer(input)

Why? In deep networks (12-96 layers), gradients can vanish.
The skip connection gives gradients a "highway" to flow through.

Module 07 mentioned this as a fix for vanishing gradients.
Here's how it works in practice.
""")

torch.manual_seed(42)

# Simulate a sublayer (like attention or FFN)
sublayer = nn.Linear(8, 8)  # a simple transformation

X = torch.randn(4, 8)  # 4 words, 8-dim

# WITHOUT residual connection
output_no_skip = sublayer(X)

# WITH residual connection
output_with_skip = X + sublayer(X)
# The "+ X" is the residual/skip connection
# Even if sublayer(X) outputs near-zero, the output still contains X

print("Without residual: output = sublayer(X)")
print(f"  Output magnitude: {output_no_skip.abs().mean().item():.4f}")
print()
print("With residual: output = X + sublayer(X)")
print(f"  Output magnitude: {output_with_skip.abs().mean().item():.4f}")
print()
print("The residual connection ensures information flows through")
print("even if the sublayer's contribution is small")
print()

# Now with LayerNorm (the full pattern)
layer_norm = nn.LayerNorm(8)
output_full = layer_norm(X + sublayer(X))
# This is the complete "Add & Norm" step:
# 1. Run sublayer on input
# 2. ADD input back (residual)
# 3. Normalize

print("Full pattern: output = LayerNorm(X + sublayer(X))")
print(f"  Output mean: {output_full.mean(dim=-1).tolist()}")
PYEOF
```

---

## Step 4. Feed-Forward Network

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

print("""
The Feed-Forward Network (FFN) in a Transformer:
  1. Expand: d_model -> 4 * d_model (make it bigger)
  2. Activate: apply GELU (a smooth version of ReLU)
  3. Compress: 4 * d_model -> d_model (bring it back)

  FFN(x) = Linear2(GELU(Linear1(x)))

Why expand then compress?
The expansion gives the model more "room to think" before
compressing back. Like using a wider intermediate table in SQL
then selecting just the columns you need.

DBA analogy:
  SELECT final_columns FROM (
    SELECT *, lots_of_computed_columns FROM data
  ) subquery
""")

torch.manual_seed(42)
d_model = 8
d_ff = 4 * d_model  # feed-forward dimension = 4x the model dimension
# d_ff = 32 in this case. Real models: d_model=768, d_ff=3072

class FeedForward(nn.Module):
    def __init__(self, d_model, d_ff):
        super().__init__()
        self.linear1 = nn.Linear(d_model, d_ff)    # expand: 8 -> 32
        self.linear2 = nn.Linear(d_ff, d_model)     # compress: 32 -> 8
        self.gelu = nn.GELU()  # activation function used in modern Transformers
        # GELU (Gaussian Error Linear Unit): smooth version of ReLU
        # Used in BERT, GPT, and most Transformers since 2018

    def forward(self, x):
        x = self.linear1(x)  # expand
        x = self.gelu(x)     # activate (add non-linearity)
        x = self.linear2(x)  # compress back
        return x

ffn = FeedForward(d_model, d_ff)
X = torch.randn(4, 8)  # 4 words, 8-dim

output = ffn(X)
print(f"Input shape:  {X.shape}")
print(f"After linear1: {ffn.linear1(X).shape} (expanded to {d_ff})")
print(f"Output shape: {output.shape} (compressed back to {d_model})")
print()

# Count parameters
params = sum(p.numel() for p in ffn.parameters())
# p.numel() counts the number of values in each parameter tensor
print(f"FFN parameters: {params}")
print(f"  linear1: {d_model} x {d_ff} + {d_ff} bias = {d_model * d_ff + d_ff}")
print(f"  linear2: {d_ff} x {d_model} + {d_model} bias = {d_ff * d_model + d_model}")
PYEOF
```

Expected output (yours will differ):

```
Input shape:  torch.Size([4, 8])
After linear1: torch.Size([4, 32]) (expanded to 32)
Output shape: torch.Size([4, 8]) (compressed back to 8)

FFN parameters: 552
  linear1: 8 x 32 + 32 bias = 288
  linear2: 32 x 8 + 8 bias = 264
```

---

## Step 5. Assemble the complete Transformer block

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn
import torch.nn.functional as F

class TransformerBlock(nn.Module):
    """One complete Transformer block."""

    def __init__(self, d_model, num_heads, d_ff, dropout=0.1):
        super().__init__()
        # d_model: embedding dimension (e.g., 768)
        # num_heads: number of attention heads (e.g., 12)
        # d_ff: feed-forward hidden dimension (e.g., 3072)
        # dropout: regularization rate (prevents overfitting)

        # Multi-Head Attention (from Build 02)
        self.attention = nn.MultiheadAttention(
            embed_dim=d_model,
            num_heads=num_heads,
            dropout=dropout,
            batch_first=True,  # input shape: [batch, seq_len, d_model]
        )

        # Feed-Forward Network (from Step 4)
        self.ffn = nn.Sequential(
            nn.Linear(d_model, d_ff),    # expand
            nn.GELU(),                    # activate
            nn.Linear(d_ff, d_model),     # compress
        )

        # Layer Norms (from Step 2)
        self.norm1 = nn.LayerNorm(d_model)  # after attention
        self.norm2 = nn.LayerNorm(d_model)  # after FFN

        # Dropout (from Module 07)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x):
        # x shape: [batch, seq_len, d_model]

        # Step 1: Multi-Head Attention + Residual + Norm
        attn_output, attn_weights = self.attention(x, x, x)
        # Self-attention: query=x, key=x, value=x (all the same input)
        x = self.norm1(x + self.dropout(attn_output))
        # Residual: add input (x) back to attention output
        # Dropout: randomly zero some values during training
        # LayerNorm: normalize to mean=0, std=1

        # Step 2: Feed-Forward + Residual + Norm
        ffn_output = self.ffn(x)
        x = self.norm2(x + self.dropout(ffn_output))
        # Same pattern: residual + dropout + normalize

        return x, attn_weights

# Build a Transformer block with BERT-like dimensions (scaled down)
torch.manual_seed(42)

d_model = 64     # embedding dimension (BERT uses 768)
num_heads = 4    # attention heads (BERT uses 12)
d_ff = 256       # feed-forward dimension (BERT uses 3072)

block = TransformerBlock(d_model, num_heads, d_ff)

# Input: batch of 2 sentences, each 6 words, 64-dim embeddings
batch_size = 2
seq_len = 6
X = torch.randn(batch_size, seq_len, d_model)

# Forward pass
block.eval()  # evaluation mode (disables dropout)
with torch.no_grad():
    output, weights = block(X)

print("Transformer Block")
print(f"  Input:  {X.shape}  = [batch={batch_size}, words={seq_len}, dims={d_model}]")
print(f"  Output: {output.shape}  = same shape (Transformer preserves shape)")
print(f"  Attention weights: {weights.shape}")
print()

# Count parameters
total_params = sum(p.numel() for p in block.parameters())
print(f"Parameters in this block: {total_params:,}")
print()

# What BERT looks like
print("Comparison to real models:")
print(f"  This block:  d_model={d_model}, heads={num_heads}, d_ff={d_ff}")
print(f"  BERT-base:   d_model=768, heads=12, d_ff=3072, blocks=12")
print(f"  BERT-base total: 110,000,000 parameters")
print(f"  GPT-3:       d_model=12288, heads=96, d_ff=49152, blocks=96")
print(f"  GPT-3 total: 175,000,000,000 parameters")
PYEOF
```

Expected output (yours will differ):

```
Transformer Block
  Input:  torch.Size([2, 6, 64])  = [batch=2, words=6, dims=64]
  Output: torch.Size([2, 6, 64])  = same shape (Transformer preserves shape)
  Attention weights: torch.Size([2, 6, 6])

Parameters in this block: 50,048

Comparison to real models:
  This block:  d_model=64, heads=4, d_ff=256
  BERT-base:   d_model=768, heads=12, d_ff=3072, blocks=12
  BERT-base total: 110,000,000 parameters
  GPT-3:       d_model=12288, heads=96, d_ff=49152, blocks=96
  GPT-3 total: 175,000,000,000 parameters
```

---

## Step 6. Stack blocks into a Transformer

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
import torch.nn as nn

class TransformerBlock(nn.Module):
    def __init__(self, d_model, num_heads, d_ff, dropout=0.1):
        super().__init__()
        self.attention = nn.MultiheadAttention(d_model, num_heads, dropout=dropout, batch_first=True)
        self.ffn = nn.Sequential(nn.Linear(d_model, d_ff), nn.GELU(), nn.Linear(d_ff, d_model))
        self.norm1 = nn.LayerNorm(d_model)
        self.norm2 = nn.LayerNorm(d_model)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x):
        attn_out, _ = self.attention(x, x, x)
        x = self.norm1(x + self.dropout(attn_out))
        x = self.norm2(x + self.dropout(self.ffn(x)))
        return x

class MiniTransformer(nn.Module):
    """A small Transformer for classification."""

    def __init__(self, vocab_size, d_model, num_heads, d_ff, num_blocks, num_classes):
        super().__init__()
        # vocab_size: how many unique tokens (e.g., 50257 for GPT-2)
        # num_blocks: how many Transformer blocks to stack
        # num_classes: output classes (e.g., 2 for positive/negative)

        # Token embedding: convert token IDs to vectors
        self.embedding = nn.Embedding(vocab_size, d_model)
        # nn.Embedding is a lookup table: token_id -> d_model-dim vector
        # It's LEARNED during training (starts random)

        # Positional encoding: add position information
        self.pos_embedding = nn.Embedding(512, d_model)
        # 512 = max sequence length
        # Each position (0, 1, 2, ...) gets its own learnable vector

        # Stack of Transformer blocks
        # _ is a throwaway variable - we don't need the loop counter, just the repetition
        # "for _ in range(4)" means "do this 4 times" without tracking which iteration
        # DBA analogy: like generate_series(1, 4) when you only care about the count
        self.blocks = nn.ModuleList([
            TransformerBlock(d_model, num_heads, d_ff)
            for _ in range(num_blocks)
        ])
        # nn.ModuleList registers each block so PyTorch tracks their parameters
        # List comprehension creates num_blocks TransformerBlock instances

        # Classification head: take the output and predict a class
        self.classifier = nn.Linear(d_model, num_classes)

    def forward(self, token_ids):
        # token_ids shape: [batch, seq_len]
        batch_size, seq_len = token_ids.shape

        # Step 1: Convert token IDs to embeddings
        x = self.embedding(token_ids)  # [batch, seq_len, d_model]

        # Step 2: Add positional embeddings
        positions = torch.arange(seq_len, device=token_ids.device)
        # torch.arange(6) = [0, 1, 2, 3, 4, 5]
        # device=... puts the tensor on the same device (CPU/GPU) as input
        x = x + self.pos_embedding(positions)
        # Each word embedding gets its position vector added

        # Step 3: Pass through all Transformer blocks
        for block in self.blocks:
            x = block(x)
        # After all blocks, each word's embedding is "enriched" with
        # information from all other words (via attention)

        # Step 4: Pool and classify
        # Take the mean of all word embeddings as the sentence representation
        sentence_embedding = x.mean(dim=1)  # [batch, d_model]
        # .mean(dim=1) averages across the sequence dimension
        logits = self.classifier(sentence_embedding)  # [batch, num_classes]

        return logits

# Build a mini Transformer
torch.manual_seed(42)

model = MiniTransformer(
    vocab_size=1000,   # small vocabulary for demo
    d_model=64,        # embedding dimension
    num_heads=4,       # attention heads
    d_ff=256,          # feed-forward dimension
    num_blocks=3,      # stack 3 blocks (BERT uses 12)
    num_classes=2,     # binary classification
)

# Count parameters
total = sum(p.numel() for p in model.parameters())
print(f"Mini Transformer: {total:,} parameters")
print()

# Test with fake token IDs
fake_input = torch.randint(0, 1000, (2, 10))
# torch.randint(low, high, shape): random integers
# 2 sentences, each 10 tokens long, IDs between 0 and 999

model.eval()
with torch.no_grad():
    logits = model(fake_input)

print(f"Input shape: {fake_input.shape} (2 sentences, 10 tokens each)")
print(f"Output shape: {logits.shape} (2 sentences, 2 class scores)")
print(f"Output: {logits}")
print()

# Convert to probabilities
probs = torch.softmax(logits, dim=-1)
# softmax converts raw scores to probabilities
print(f"Probabilities: {probs}")
print(f"Predicted classes: {probs.argmax(dim=-1).tolist()}")
# argmax returns the index of the highest probability
print()

# Architecture summary
print("Architecture:")
print(f"  1. Embedding: token_id -> {64}-dim vector")
print(f"  2. Position:  add position information")
print(f"  3. Blocks:    {3} x [Attention -> Add&Norm -> FFN -> Add&Norm]")
print(f"  4. Pool:      mean of all token embeddings")
print(f"  5. Classify:  linear layer -> {2} classes")
PYEOF
```

Expected output (yours will differ):

```
Mini Transformer: 218,626 parameters

Input shape: torch.Size([2, 10]) (2 sentences, 10 tokens each)
Output shape: torch.Size([2, 2]) (2 sentences, 2 class scores)

Probabilities: tensor([[0.45, 0.55],
                        [0.52, 0.48]])
Predicted classes: [1, 0]

Architecture:
  1. Embedding: token_id -> 64-dim vector
  2. Position:  add position information
  3. Blocks:    3 x [Attention -> Add&Norm -> FFN -> Add&Norm]
  4. Pool:      mean of all token embeddings
  5. Classify:  linear layer -> 2 classes
```

---

## What You Learned

| Component | Purpose | DBA Analogy |
|-----------|---------|-------------|
| Token Embedding | Convert token IDs to vectors | Lookup table (enum -> data) |
| Positional Encoding | Add word order information | Sequence column for ORDER BY |
| Multi-Head Attention | Find relationships between words | Multi-index JOIN with relevance scores |
| Add & Norm | Stabilize deep networks | Checkpoint + normalize intermediate results |
| Feed-Forward Network | Process each word independently | Row-level computation (CASE WHEN) |
| Stacking blocks | Build depth for complex patterns | Nested subqueries, each refining the result |
| Classification head | Map to final prediction | Final SELECT that returns what you need |
