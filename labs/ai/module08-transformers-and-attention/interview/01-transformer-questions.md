# Interview 01: Transformer Questions

Five questions you might get in an interview about Transformers and the attention mechanism.

---

## Question 1: Explain the Attention Mechanism

**Question:** What is attention in a Transformer, and why was it a breakthrough?

**Strong answer:**

**Attention lets a model look at ALL words in a sentence at once and decide which ones matter most for each word.**

Before Transformers (2017), models like RNNs read text left-to-right, one word at a time. This had two problems:
1. **Slow** - you can't parallelize sequential processing
2. **Forgetful** - by the time you reach word 100, you've mostly forgotten word 1

Attention solves both:
- **Parallel** - all words are processed simultaneously
- **Direct connections** - any word can directly "attend to" any other word, regardless of distance

**How it works:**
1. Each word produces three vectors: Query (what am I looking for?), Key (what do I contain?), Value (what info do I carry?)
2. Score every Query against every Key using dot product
3. Scale by sqrt(d_k) to prevent extreme values
4. Apply softmax to get attention weights (probabilities summing to 1)
5. Multiply weights by Values to get the output

**The formula:** `Attention(Q, K, V) = softmax(Q @ K^T / sqrt(d_k)) @ V`

**DBA analogy:** Before attention, it was like reading a table row by row (sequential scan). Attention is like having an index - you jump directly to the relevant data.

---

## Question 2: What Is the Difference Between BERT and GPT?

**Question:** Explain the architectural differences between BERT and GPT and when you'd use each.

**Strong answer:**

**Both use the Transformer architecture, but they're trained differently and serve different purposes.**

| | BERT | GPT |
|---|---|---|
| Architecture | Encoder-only | Decoder-only |
| Direction | Reads ALL words at once (bidirectional) | Reads left-to-right only |
| Training | Predicts MASKED words in a sentence | Predicts the NEXT word |
| Output | Understanding of text | Generation of text |
| Best for | Classification, search, embeddings | Chat, code generation, writing |
| Examples | BERT, RoBERTa, DeBERTa | GPT-4, Claude, LLaMA |

**When to use each:**

- **BERT-style (encoder):** When you need to UNDERSTAND text
  - Classify database alerts as critical/warning/info
  - Create embeddings for RAG search (Module 03)
  - Extract entities from log messages

- **GPT-style (decoder):** When you need to GENERATE text
  - Chat with users about database issues
  - Generate SQL from natural language
  - Write incident reports

**Key insight:** BERT sees the whole sentence at once (like knowing the answer to a crossword). GPT sees only what came before (like writing a story word by word). BERT is better for understanding; GPT is better for generating.

---

## Question 3: Why Does Tokenization Matter?

**Question:** You're building a RAG system for PostgreSQL documentation. Your search returns irrelevant results. How could tokenization be the cause?

**Strong answer:**

**Tokenization splits text into subwords, and technical terms get destroyed in the process.**

Example: `pg_stat_replication` becomes `['pg', '_stat', '_repl', 'ication']`

The model sees 4 generic pieces, not one specific PostgreSQL view. When you search for `pg_stat_replication`, the model might match:
- Documents about "statistics" (because of `_stat`)
- Documents about "replication" (because of `_repl` + `ication`)
- But NOT the specific documentation for that view

**Four fixes:**

1. **Add context to queries:** Instead of searching "pg_stat_replication", search "pg_stat_replication PostgreSQL view for monitoring streaming replication"

2. **Use domain-specific models:** Models fine-tuned on code (CodeBERT) handle technical terms better than general BERT

3. **Hybrid search:** Combine vector similarity (catches meaning) with keyword matching (catches exact terms). Score = 0.7 * cosine_sim + 0.3 * keyword_match

4. **Better chunking:** Split documents by concept, not by page. Each chunk should be about one specific topic

**Key insight:** Tokenization is invisible but affects everything downstream. When embeddings or search fail, check tokenization first.

---

## Question 4: How Do Transformers Scale?

**Question:** GPT-2 has 124M parameters, GPT-3 has 175B. What changes when you scale up a Transformer?

**Strong answer:**

**Three things can scale:**

1. **d_model** (embedding dimension): How rich each word's representation is
   - GPT-2: 768 dimensions
   - GPT-3: 12,288 dimensions

2. **Number of blocks** (depth): How many Transformer layers are stacked
   - GPT-2: 12 blocks
   - GPT-3: 96 blocks

3. **Number of heads** (width): How many parallel attention patterns per block
   - GPT-2: 12 heads
   - GPT-3: 96 heads

**What scaling gives you:**
- More capacity to learn complex patterns
- Better performance on harder tasks
- Emergent abilities (things small models can't do at all, like chain-of-thought reasoning)

**What scaling costs:**
- Training: GPT-3 cost an estimated $4.6 million to train
- Inference: Larger models are slower and more expensive per token
- Data: Need proportionally more training data
- Memory: GPT-3 needs ~350GB just to load the weights

**Scaling laws (Chinchilla):** There's an optimal ratio between model size and training data. A 10x larger model needs roughly 10x more data to be worth it. Training a huge model on too little data wastes compute.

**Practical implication:** For most DBA tasks (alert classification, embeddings for RAG), a small model (BERT-base, 110M params) is sufficient. Only reach for large models when you need generation quality (Claude, GPT-4).

---

## Question 5: Explain the Context Window and Its Limitations

**Question:** Your application sends database logs to an LLM for analysis, but it fails on large logs. What's happening and how do you fix it?

**Strong answer:**

**The context window is the maximum number of tokens a model can process at once.**

| Model | Context Window |
|-------|---------------|
| BERT | 512 tokens |
| GPT-2 | 1,024 tokens |
| GPT-4 | 128,000 tokens |
| Claude | 200,000 tokens |

**Why it's limited:** Attention computes scores between EVERY pair of tokens. With N tokens, that's N^2 operations. Doubling the context length quadruples the compute.

**What happens when you exceed it:**
- Some models silently truncate (DANGER - you lose data without knowing)
- Some models throw an error
- Some models degrade in quality (attention gets "spread thin" over too many tokens)

**Five fixes for large inputs:**

1. **Filter first:** For database logs, filter by severity (ERROR, FATAL, WARNING) before sending. 50,000 log lines might have only 50 important ones.

2. **Smart truncation:** Keep the first 30% and last 70% of the text. Database errors are usually at the END of logs.

3. **Chunking:** Split into overlapping chunks, process each separately, combine results.

4. **Summarize progressively:** Summarize the first chunk, then include the summary with the next chunk. This "compresses" earlier context.

5. **Use the right model:** If you need to analyze 10,000 lines, use a model with a large context window (Claude at 200K tokens, not BERT at 512).

**Prevention:** Always count tokens before sending. `len(tokenizer.encode(text))` takes milliseconds and prevents runtime failures.
