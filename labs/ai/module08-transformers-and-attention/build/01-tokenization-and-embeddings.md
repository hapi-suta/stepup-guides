# Build 01: Tokenization & Embeddings

Every Transformer starts the same way: convert text to numbers. This guide shows you exactly how that works - from raw text to token IDs to embedding vectors.

---

## Step 1. Install the tools

On your **Mac terminal**, run:

```bash
pip3 install transformers
```

This installs HuggingFace Transformers - the most popular library for working with pre-trained Transformer models. It gives you access to thousands of models (BERT, GPT-2, etc.) with a few lines of code.

If you already have it installed, pip will say "Requirement already satisfied."

---

## Step 2. See tokenization in action

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import AutoTokenizer  # AutoTokenizer picks the right tokenizer for any model

# Load GPT-2's tokenizer (small, fast download)
tokenizer = AutoTokenizer.from_pretrained("gpt2")
# from_pretrained() downloads the tokenizer files from HuggingFace
# First run downloads ~1MB, then it's cached locally

# Tokenize a simple sentence
text = "The PostgreSQL database is running slow"
tokens = tokenizer.encode(text)  # encode() converts text -> list of token IDs
# Each token ID is an integer that maps to a piece of text in the vocabulary

print(f"Original text: {text}")
print(f"Token IDs:     {tokens}")
print(f"Number of tokens: {len(tokens)}")
print()

# See what each token ID maps to
for token_id in tokens:
    token_text = tokenizer.decode([token_id])  # decode() converts token ID back to text
    print(f"  ID {token_id:>6d} -> '{token_text}'")

print()

# Important: tokens are NOT always full words
text2 = "PostgreSQL replication lag exceeded threshold"
tokens2 = tokenizer.encode(text2)
decoded2 = [tokenizer.decode([t]) for t in tokens2]  # list comprehension: do decode for each token
print(f"Text: {text2}")
print(f"Tokens: {decoded2}")
print(f"Count: {len(tokens2)} tokens")
print()
print("Notice: 'PostgreSQL' becomes multiple tokens ('Post', 'gres', 'QL')")
print("Rare words get split into smaller pieces (subword tokenization)")
PYEOF
```

Expected output (yours will differ):

```
Original text: The PostgreSQL database is running slow
Token IDs:     [464, 2947, 47701, 6831, 318, 2491, 3105]
Number of tokens: 7

  ID    464 -> 'The'
  ID   2947 -> ' Post'
  ID  47701 -> 'gres'
  ...

Text: PostgreSQL replication lag exceeded threshold
Tokens: ['Post', 'gres', 'QL', ' replication', ' lag', ' exceeded', ' threshold']
Count: 7 tokens

Notice: 'PostgreSQL' becomes multiple tokens ('Post', 'gres', 'QL')
Rare words get split into smaller pieces (subword tokenization)
```

---

## Step 3. Why tokenization matters for you

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("gpt2")

# Token count affects:
# 1. API costs (you pay per token)
# 2. Context window (models have a token limit)
# 3. Speed (more tokens = slower processing)

examples = [
    "SELECT * FROM users",                                    # Simple SQL
    "SELECT u.name, o.total FROM users u JOIN orders o ON u.id = o.user_id WHERE o.total > 100",  # Complex SQL
    "The server with IP 192.168.1.100 is experiencing high CPU usage",  # English
    "cpu_usage > 80 AND memory_usage > 90 AND connection_count > 200",  # Conditions
]

print(f"{'Text':60s}  Tokens")
print("-" * 75)

for text in examples:
    tokens = tokenizer.encode(text)
    # Display first 40 chars of text, then token count
    display = text[:57] + "..." if len(text) > 60 else text
    print(f"{display:60s}  {len(tokens):>3d}")

print()
print("Key insight: SQL and code use MORE tokens than English")
print("because technical terms get split into subwords.")
print()

# Show the vocabulary size
print(f"GPT-2 vocabulary size: {tokenizer.vocab_size:,} tokens")
print("That means GPT-2 knows 50,257 'words' (including subwords)")
PYEOF
```

Expected output (yours will differ):

```
Text                                                          Tokens
---------------------------------------------------------------------------
SELECT * FROM users                                              5
SELECT u.name, o.total FROM users u JOIN orders o ON u...       27
The server with IP 192.168.1.100 is experiencing high ...       16
cpu_usage > 80 AND memory_usage > 90 AND connection_co...       18

Key insight: SQL and code use MORE tokens than English
because technical terms get split into subwords.

GPT-2 vocabulary size: 50,257 tokens
```

---

## Step 4. From token IDs to embeddings

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
from transformers import AutoTokenizer, AutoModel  # AutoModel loads the full model (not just tokenizer)

# Load a small BERT model (good for understanding embeddings)
model_name = "bert-base-uncased"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModel.from_pretrained(model_name)
# This downloads ~440MB the first time (the full BERT model)
# "uncased" means it treats "Database" and "database" the same

# Tokenize
text = "The database connection pool is exhausted"
inputs = tokenizer(text, return_tensors="pt")
# return_tensors="pt" means return PyTorch tensors (not plain lists)
# "pt" = PyTorch, "tf" = TensorFlow, "np" = NumPy

print(f"Text: {text}")
print(f"Input IDs shape: {inputs['input_ids'].shape}")
# Shape is [1, N] where 1 = one sentence, N = number of tokens
print(f"Token IDs: {inputs['input_ids'][0].tolist()}")
# [0] gets the first (only) sentence, .tolist() converts tensor to Python list
print()

# Get embeddings from the model
with torch.no_grad():  # no_grad() = we're not training, just getting outputs
    outputs = model(**inputs)
    # **inputs unpacks the dictionary: model(input_ids=..., attention_mask=...)
    # The model processes all tokens through 12 Transformer blocks

# outputs.last_hidden_state contains the embedding for each token
embeddings = outputs.last_hidden_state  # shape: [1, num_tokens, 768]
print(f"Embedding shape: {embeddings.shape}")
print(f"  Batch size: {embeddings.shape[0]} (one sentence)")
print(f"  Tokens: {embeddings.shape[1]}")
print(f"  Embedding dimension: {embeddings.shape[2]} (each token becomes 768 numbers)")
print()

# Each token is now a 768-dimensional vector
tokens = tokenizer.convert_ids_to_tokens(inputs['input_ids'][0])
# convert_ids_to_tokens shows the actual token text for each ID

for i, token in enumerate(tokens):
    vec = embeddings[0, i]  # embedding for token i
    # [0] = first sentence, [i] = i-th token
    print(f"  '{token:15s}' -> [{vec[0]:.4f}, {vec[1]:.4f}, {vec[2]:.4f}, ...] (768 dims)")

print()
print("Each token started as a single number (token ID)")
print("BERT converted each one into a 768-number vector that captures MEANING")
print("These vectors are what attention operates on")
PYEOF
```

Expected output (yours will differ):

```
Text: The database connection pool is exhausted
Input IDs shape: torch.Size([1, 8])
Token IDs: [101, 1996, 4927, 4434, 4770, 2003, 15454, 102]

Embedding shape: torch.Size([1, 8, 768])
  Batch size: 1 (one sentence)
  Tokens: 8
  Embedding dimension: 768 (each token becomes 768 numbers)

  '[CLS]          ' -> [0.1234, -0.5678, 0.2345, ...] (768 dims)
  'the            ' -> [0.3456, -0.1234, 0.7890, ...] (768 dims)
  'database       ' -> [0.5678, 0.2345, -0.3456, ...] (768 dims)
  ...
```

---

## Step 5. Sentence embeddings for similarity

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
from transformers import AutoTokenizer, AutoModel

# Load BERT
tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")
model = AutoModel.from_pretrained("bert-base-uncased")

def get_sentence_embedding(text):
    """Convert a sentence to a single embedding vector."""
    inputs = tokenizer(text, return_tensors="pt", padding=True, truncation=True)
    # padding=True: pad shorter sentences so all have same length
    # truncation=True: cut sentences that exceed max length (512 tokens for BERT)

    with torch.no_grad():
        outputs = model(**inputs)

    # Mean pooling: average all token embeddings into one sentence embedding
    # This is a simple but effective way to get a sentence-level vector
    embedding = outputs.last_hidden_state.mean(dim=1)
    # .mean(dim=1) averages across the token dimension
    # Shape goes from [1, num_tokens, 768] -> [1, 768]
    return embedding[0]  # [0] removes the batch dimension -> shape [768]

# DBA-related sentences
sentences = [
    "The database replication lag is increasing",
    "PostgreSQL standby is falling behind the primary",
    "The weather is sunny today",
    "Connection pool is exhausted on the primary server",
    "My cat likes to sleep on the keyboard",
]

print("Computing sentence embeddings...")
embeddings = [get_sentence_embedding(s) for s in sentences]
# List comprehension: compute embedding for each sentence

print()
print("Cosine similarity between sentences:")
print("(1.0 = identical meaning, 0.0 = unrelated)")
print()

# Compare first sentence to all others
from torch.nn.functional import cosine_similarity
# cosine_similarity measures how similar two vectors are (Module 05)

reference = sentences[0]
ref_emb = embeddings[0]

for i, (sent, emb) in enumerate(zip(sentences, embeddings)):
    # zip() pairs sentences with their embeddings
    # enumerate() adds an index number
    sim = cosine_similarity(ref_emb.unsqueeze(0), emb.unsqueeze(0)).item()
    # unsqueeze(0) adds batch dimension: [768] -> [1, 768]
    # .item() converts single-value tensor to Python float
    marker = " <-- reference" if i == 0 else ""
    print(f"  {sim:.3f}  '{sent}'{marker}")

print()
print("Notice: database-related sentences score higher against each other")
print("The model UNDERSTANDS meaning, not just keyword matching")
PYEOF
```

Expected output (yours will differ):

```
Computing sentence embeddings...

Cosine similarity between sentences:
(1.0 = identical meaning, 0.0 = unrelated)

  1.000  'The database replication lag is increasing' <-- reference
  0.812  'PostgreSQL standby is falling behind the primary'
  0.423  'The weather is sunny today'
  0.756  'Connection pool is exhausted on the primary server'
  0.298  'My cat likes to sleep on the keyboard'

Notice: database-related sentences score higher against each other
The model UNDERSTANDS meaning, not just keyword matching
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Tokenization | Splits text into token IDs | Like storing enums instead of strings |
| Subword tokenization | Rare words get split into pieces | Like breaking "PostgreSQL" into prefix + root |
| Vocabulary | Maps between text and token IDs | Like a lookup table / dictionary |
| Embeddings | Each token ID becomes a 768-dim vector | Like converting a category to a feature vector |
| Sentence embedding | Average all token vectors into one | Like aggregating row-level data to table-level |
| Cosine similarity | Measures how similar two embeddings are | Like a fuzzy JOIN on meaning, not exact match |
