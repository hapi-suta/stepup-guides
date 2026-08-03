# USE 01: Transformer Exercises

Practice what you built. Each exercise reinforces a concept from Builds 01-04.

---

## Exercise 1: Token Counter (Build 01)

Build a function that counts tokens for different models and estimates API cost.

**Task:**
1. Load tokenizers for both `gpt2` and `bert-base-uncased`
2. Create a list of 5 SQL queries of varying complexity
3. Tokenize each query with both tokenizers
4. Print a comparison table showing: query (first 40 chars), GPT-2 token count, BERT token count
5. Calculate estimated API cost at $0.01 per 1000 tokens for each query

**Hint:** `tokenizer.encode(text)` returns a list of token IDs. `len()` gives you the count.

---

## Exercise 2: Similarity Search (Build 01)

Build a simple search engine using sentence embeddings.

**Task:**
1. Create a list of 10 PostgreSQL error messages (e.g., "connection refused", "disk full", "replication lag")
2. Use BERT to compute embeddings for all 10 messages
3. Write a `search(query)` function that:
   - Computes the embedding for the query
   - Calculates cosine similarity against all 10 messages
   - Returns the top 3 most similar messages with scores
4. Test with: "server is not responding" (should match "connection refused" type errors)
5. Test with: "running out of space" (should match "disk full" type errors)

**Hint:** Use the `get_sentence_embedding()` function from Build 01 Step 5.

---

## Exercise 3: Attention Visualization (Build 02)

Explore what attention actually learns.

**Task:**
1. Build a scaled dot-product attention function (from Build 02)
2. Create embeddings for the sentence: "The primary database server replicated to the standby"
3. Compute attention weights
4. Print the attention matrix as a formatted grid
5. Identify which word "standby" pays the most attention to (should relate to "replicated" or "primary")

**Hint:** Use `torch.randn()` to simulate embeddings if you don't want to load BERT.

---

## Exercise 4: Alert Classifier (Build 04)

Build a zero-shot alert classifier for database operations.

**Task:**
1. Use `pipeline("zero-shot-classification")`
2. Define 6 categories: `performance`, `storage`, `replication`, `security`, `backup`, `connection`
3. Create 12 realistic database alert messages (2 per category)
4. Classify each alert and check if the model gets the correct category
5. Print accuracy: how many did the model classify correctly?
6. Print a confusion-style report showing which categories get confused with each other

**Expected outcome:** The model should get 8+ out of 12 correct without any training.

---

## Exercise 5: Build a Transformer Classifier (Build 03)

Build and train a mini Transformer from scratch for classification.

**Task:**
1. Create a synthetic dataset: 500 "sequences" of random token IDs, 10 tokens each
2. Label: class 1 if the sequence contains token ID 42 or 99, class 0 otherwise
3. Build a `MiniTransformer` (from Build 03 Step 6) with:
   - vocab_size=100, d_model=32, num_heads=2, d_ff=64, num_blocks=2, num_classes=2
4. Train for 50 epochs with CrossEntropyLoss and Adam optimizer
5. Report test accuracy (target: > 80%)

**Changes from Module 07 neural network:**
- Input: token IDs (integers), not float features
- Model: Transformer blocks instead of nn.Linear layers
- Embedding layer converts token IDs to vectors

**Hint:** `torch.randint(0, 100, (500, 10))` creates random token sequences.

---

## Scoring Guide

| Exercise | Skill Tested | Difficulty |
|----------|-------------|------------|
| 1 | Tokenization and token counting | Beginner |
| 2 | Embeddings and similarity search | Beginner |
| 3 | Attention mechanism understanding | Intermediate |
| 4 | Pre-trained models for real tasks | Intermediate |
| 5 | Building and training a Transformer | Advanced |
