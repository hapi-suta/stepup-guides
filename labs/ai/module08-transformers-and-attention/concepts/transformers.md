# Transformers & Attention - Concepts

This is the architecture behind every modern AI model - ChatGPT, Claude, BERT, and all LLMs. If Module 07 taught you how neural networks learn, this module teaches you the specific type of neural network that changed everything.

---

## Why Should You Care?

Every AI tool you use - Claude, GitHub Copilot, text-to-SQL - runs on a Transformer. When you:

- Ask Claude to explain a query plan, a Transformer processes your text
- Use RAG to search documentation (Module 03), a Transformer creates the embeddings
- Fine-tune a model for your database alerts (Module 09), you're fine-tuning a Transformer

Understanding Transformers means understanding WHY these tools work, not just that they work.

---

## The DBA Analogy

Think of how PostgreSQL processes a query:

| PostgreSQL | Transformer |
|-----------|-------------|
| Full table scan (reads every row) | RNN - reads words one at a time, left to right |
| Index lookup (jumps to relevant rows) | Attention - jumps directly to relevant words |
| Composite index (multiple columns) | Multi-head attention - looks at multiple relationships |
| Query plan (decides what to read) | Attention weights (decides what to focus on) |
| Parallel query (multiple workers) | Parallel attention (all words processed at once) |

The key insight: **before Transformers, models read text one word at a time (like a full table scan). Transformers read ALL words at once and use attention to figure out which words matter (like an index lookup).**

---

## The History in 30 Seconds

1. **Before 2017:** RNNs and LSTMs processed text one word at a time. Slow. Forgot early words in long sentences.
2. **2017:** Google published "Attention Is All You Need." Introduced the Transformer. Processed all words in parallel.
3. **2018:** Google released BERT (Transformer that reads both directions). Dominated NLP benchmarks.
4. **2019-now:** GPT-2, GPT-3, GPT-4, Claude - all decoder-only Transformers, scaled to billions of parameters.

One paper changed the entire field. That's rare.

---

## Key Concepts

### 1. Tokenization - Turning Text Into Numbers

Neural networks only understand numbers. Tokenization converts text to numbers.

```
"The database is slow" -> [464, 6831, 318, 3105]
```

Each number is a token ID. The model has a vocabulary (like a dictionary) mapping words to IDs.

**DBA analogy:** This is like an enum. Instead of storing "healthy", "warning", "critical" as strings, you store 0, 1, 2. Same idea - map text to integers.

### 2. Embeddings - Giving Tokens Meaning

Each token ID gets converted to a vector (a list of numbers). You learned about vectors in Module 05.

```
Token 464 ("The")      -> [0.12, -0.34, 0.56, ...] (768 numbers)
Token 6831 ("database") -> [0.89, 0.23, -0.11, ...] (768 numbers)
```

Similar words have similar vectors. "database" and "table" would be closer together than "database" and "banana."

**DBA analogy:** You already used embeddings in Module 03 (RAG). Those came from a Transformer model.

### 3. Attention - The Core Innovation

Attention answers: "When processing this word, which OTHER words should I focus on?"

Example sentence: "The server crashed because it ran out of memory."

When processing "it", the model needs to know "it" refers to "server." Attention creates a score between every pair of words:

```
"it" paying attention to:
  "server"  -> 0.72 (high - "it" refers to "server")
  "crashed" -> 0.15 (some relevance)
  "The"     -> 0.02 (low - not important)
  "memory"  -> 0.11 (some relevance)
```

**DBA analogy:** Attention is like a JOIN with a relevance score. Instead of just matching on exact keys (WHERE a.id = b.id), attention gives a soft match - how relevant is every row to every other row.

### 4. Multi-Head Attention - Multiple Perspectives

One attention head might learn grammar (subject-verb agreement). Another might learn meaning (what "it" refers to). Another might learn position (nearby words matter more).

Multiple heads = multiple ways to analyze relationships between words.

**DBA analogy:** Like running the same query with different indexes. Each index reveals different patterns in the data. Multi-head attention is like having 12 different indexes and combining what each one finds.

### 5. Positional Encoding - Word Order

Since Transformers process all words in parallel (not left-to-right), they don't naturally know word order. "Dog bites man" and "Man bites dog" would look the same.

Positional encoding adds a pattern to each word's embedding that tells the model its position:

```
Word 1 embedding + position_1_pattern = knows it's first
Word 2 embedding + position_2_pattern = knows it's second
```

**DBA analogy:** Like adding a sequence number column. Without it, rows in a table have no guaranteed order. The positional encoding is the ORDER BY.

### 6. The Transformer Block

One Transformer block has these steps:

```
Input
  -> Multi-Head Attention (which words relate to which?)
  -> Add & Normalize (residual connection + layer norm)
  -> Feed-Forward Network (process each position independently)
  -> Add & Normalize (another residual connection)
Output
```

A real model stacks many of these blocks:
- BERT-base: 12 blocks
- GPT-2: 12 blocks
- GPT-3: 96 blocks
- Claude: many blocks (exact number not published)

More blocks = more capacity to learn complex patterns = more parameters = needs more data and compute.

### 7. Encoder vs Decoder

The original Transformer had two halves:

| Architecture | What It Does | Examples | Use Case |
|-------------|-------------|----------|----------|
| Encoder-only | Reads all words, outputs understanding | BERT, RoBERTa | Classification, embeddings, search |
| Decoder-only | Generates text one word at a time | GPT, Claude, LLaMA | Chat, code generation, writing |
| Encoder-Decoder | Reads input, generates output | T5, BART | Translation, summarization |

**What you use as a DBA:**
- Encoder models: When you create embeddings for RAG (Module 03)
- Decoder models: When you chat with Claude or use Copilot

---

## What You Don't Need

- You do NOT need to implement a full Transformer from scratch for production
- You do NOT need to understand the math behind positional encoding formulas
- You do NOT need to know the differences between every Transformer variant
- You DO need to understand attention (it's the foundation of everything in AI right now)
- You DO need to understand tokenization (it affects prompt engineering and costs)
- You DO need to know encoder vs decoder (determines which model to pick)

---

## What You'll Build

| Build | What | Why |
|-------|------|-----|
| 01 - Tokenization & Embeddings | Turn text into tokens and explore embeddings | Foundation - every Transformer starts here |
| 02 - Attention from Scratch | Build the attention mechanism step by step | Core innovation - understand what makes Transformers work |
| 03 - Transformer Block | Assemble a complete Transformer block | See how attention, normalization, and feed-forward connect |
| 04 - Using Pre-trained Transformers | Load and use real Transformer models | Practical skill - use HuggingFace for real tasks |
