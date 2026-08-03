# Build 04: Using Pre-trained Transformers

Builds 01-03 taught you how Transformers work inside. This guide teaches the practical skill: loading and using real pre-trained models from HuggingFace for actual tasks.

---

## Step 1. The HuggingFace pipeline - easiest way to use Transformers

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import pipeline
# pipeline() is HuggingFace's highest-level API
# It handles tokenization, model loading, and output formatting automatically

# Sentiment Analysis (classification)
classifier = pipeline("sentiment-analysis")
# This downloads a default model (~270MB first time)
# Default model: distilbert-base-uncased-finetuned-sst-2-english

results = classifier([
    "The database migration completed successfully",
    "Server crashed and we lost 3 hours of data",
    "The backup finished but took longer than expected",
    "Critical alert: replication lag exceeding 5 minutes",
])

print("Sentiment Analysis:")
print("-" * 60)
for text, result in zip([
    "The database migration completed successfully",
    "Server crashed and we lost 3 hours of data",
    "The backup finished but took longer than expected",
    "Critical alert: replication lag exceeding 5 minutes",
], results):
    print(f"  {result['label']:>8s} ({result['score']:.3f})  {text}")
    # result['label'] = POSITIVE or NEGATIVE
    # result['score'] = confidence (0 to 1)

print()
print("The model classifies text as POSITIVE or NEGATIVE")
print("Score shows confidence (closer to 1.0 = more confident)")
PYEOF
```

Expected output (yours will differ):

```
Sentiment Analysis:
------------------------------------------------------------
  POSITIVE (0.999)  The database migration completed successfully
  NEGATIVE (0.999)  Server crashed and we lost 3 hours of data
  NEGATIVE (0.874)  The backup finished but took longer than expected
  NEGATIVE (0.997)  Critical alert: replication lag exceeding 5 minutes
```

---

## Step 2. Text classification - classify database alerts

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import pipeline

# Zero-shot classification: classify text into categories
# WITHOUT training a new model - the model figures it out from the labels
classifier = pipeline("zero-shot-classification")
# Default model: facebook/bart-large-mnli (~1.6GB first time)

# Database alert messages
alerts = [
    "CPU usage on pg-primary-1 has been above 95% for 10 minutes",
    "Nightly backup to S3 completed in 45 minutes",
    "Replication lag on pg-standby-2 jumped to 120 seconds",
    "New user table created by developer team",
    "Disk space on /pgdata is at 92% capacity",
]

# Categories we want to classify into
categories = ["performance", "backup", "replication", "schema change", "storage"]

print("Zero-Shot Alert Classification")
print("(No training needed - the model understands the categories)")
print("=" * 70)

for alert in alerts:
    result = classifier(alert, categories)
    # result['labels'] = categories sorted by score (highest first)
    # result['scores'] = confidence score for each category
    top_label = result['labels'][0]    # most likely category
    top_score = result['scores'][0]    # confidence for top category
    print(f"\n  Alert: {alert}")
    print(f"  Class: {top_label} ({top_score:.1%})")

    # Show all scores
    for label, score in zip(result['labels'], result['scores']):
        bar = "#" * int(score * 30)  # visual bar (30 chars wide)
        print(f"    {label:>15s}: {score:.3f} {bar}")

print()
print("Zero-shot classification uses the model's pre-trained knowledge")
print("to classify text into ANY categories you provide - no training needed")
PYEOF
```

Expected output (yours will differ):

```
Zero-Shot Alert Classification
(No training needed - the model understands the categories)
======================================================================

  Alert: CPU usage on pg-primary-1 has been above 95% for 10 minutes
  Class: performance (0.924)
    performance: 0.924 ############################
        storage: 0.032 #
    replication: 0.021
         backup: 0.013
  schema change: 0.010
```

---

## Step 3. Text generation - generate database documentation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import pipeline

# Text generation using GPT-2
generator = pipeline("text-generation", model="gpt2")
# GPT-2 is a decoder-only Transformer (like Claude, but much smaller)
# 124M parameters vs Claude's much larger size

prompts = [
    "To optimize a slow PostgreSQL query, you should first",
    "The most common cause of database replication lag is",
    "When a database backup fails, the DBA should immediately",
]

print("GPT-2 Text Generation (124M parameters)")
print("=" * 60)

for prompt in prompts:
    result = generator(
        prompt,
        max_new_tokens=50,     # generate at most 50 new tokens
        num_return_sequences=1, # return 1 completion
        do_sample=True,         # use sampling (adds randomness)
        temperature=0.7,        # lower = more focused, higher = more creative
        # temperature controls randomness:
        #   0.0 = always pick the most likely next token (deterministic)
        #   0.7 = mostly likely tokens with some variety (good default)
        #   1.5 = very random (creative but may be nonsensical)
    )
    generated = result[0]['generated_text']
    # result is a list (one per num_return_sequences)
    # Each item has 'generated_text' with the prompt + generated continuation

    print(f"\nPrompt: {prompt}")
    print(f"Output: {generated}")

print()
print()
print("NOTE: GPT-2 is small (2019, 124M params) so output quality is limited")
print("Modern models (Claude, GPT-4) use the same architecture but are")
print("1000x larger with much better training data")
PYEOF
```

---

## Step 4. Feature extraction - get embeddings for downstream tasks

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import torch
from transformers import AutoTokenizer, AutoModel
import numpy as np

# This is what Module 03 (RAG) does behind the scenes
# Load a model optimized for creating embeddings
model_name = "bert-base-uncased"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModel.from_pretrained(model_name)
model.eval()  # set to evaluation mode

def get_embedding(text):
    """Get a sentence embedding from BERT."""
    inputs = tokenizer(text, return_tensors="pt", padding=True, truncation=True, max_length=128)
    # max_length=128: truncate to 128 tokens (BERT max is 512)
    with torch.no_grad():
        outputs = model(**inputs)
    # Mean pooling: average all token embeddings
    return outputs.last_hidden_state.mean(dim=1).squeeze().numpy()
    # .squeeze() removes batch dimension: [1, 768] -> [768]
    # .numpy() converts PyTorch tensor to NumPy array

# Database operations to embed
operations = [
    "SELECT * FROM users WHERE active = true",
    "SELECT * FROM customers WHERE status = 'active'",
    "INSERT INTO logs (message) VALUES ('server started')",
    "DROP TABLE IF EXISTS temp_data",
    "CREATE INDEX idx_users_email ON users(email)",
    "VACUUM ANALYZE users",
]

print("Computing BERT embeddings for SQL operations...")
embeddings = [get_embedding(op) for op in operations]
# list comprehension: compute embedding for each operation
print(f"Each operation becomes a {len(embeddings[0])}-dimensional vector")
print()

# Compute similarity matrix
from numpy.linalg import norm
# norm computes the length (magnitude) of a vector

def cosine_sim(a, b):
    """Cosine similarity between two vectors."""
    return np.dot(a, b) / (norm(a) * norm(b))
    # dot product divided by product of magnitudes
    # Returns value between -1 and 1 (1 = identical, 0 = unrelated)

print("Similarity between operations:")
print(f"{'':>5s}", end="")
for i in range(len(operations)):
    print(f"  [{i}]", end="")
print()

for i in range(len(operations)):
    print(f"  [{i}]", end="")
    for j in range(len(operations)):
        sim = cosine_sim(embeddings[i], embeddings[j])
        print(f" {sim:.2f}", end="")
    print(f"  {operations[i][:45]}")

print()
print("Notice:")
print("  [0] SELECT active users and [1] SELECT active customers are MOST similar")
print("  [4] CREATE INDEX and [5] VACUUM are somewhat similar (maintenance ops)")
print("  [0] SELECT and [3] DROP TABLE are LEAST similar (different operations)")
print()
print("This is exactly how RAG finds relevant documents -")
print("embed the query, embed the documents, find the closest match")
PYEOF
```

Expected output (yours will differ):

```
Similarity between operations:
        [0]  [1]  [2]  [3]  [4]  [5]
  [0]  1.00 0.92 0.78 0.73 0.76 0.72  SELECT * FROM users WHERE active = true
  [1]  0.92 1.00 0.77 0.72 0.75 0.71  SELECT * FROM customers WHERE status = 'a
  [2]  0.78 0.77 1.00 0.76 0.74 0.73  INSERT INTO logs (message) VALUES ('server
  [3]  0.73 0.72 0.76 1.00 0.78 0.75  DROP TABLE IF EXISTS temp_data
  [4]  0.76 0.75 0.74 0.78 1.00 0.82  CREATE INDEX idx_users_email ON users(emai
  [5]  0.72 0.71 0.73 0.75 0.82 1.00  VACUUM ANALYZE users
```

---

## Step 5. Named Entity Recognition - extract info from logs

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import pipeline

# NER: find and label entities (names, locations, etc.) in text
ner = pipeline("ner", aggregation_strategy="simple")
# aggregation_strategy="simple" merges multi-token entities
# Without it, "New York" would be two separate entities

log_messages = [
    "Engineer John Smith restarted pg-primary-1 in us-east-1 at 3:45 AM",
    "Microsoft Azure SQL instance db-prod-west failed health check",
    "Amazon RDS PostgreSQL backup for acme-corp completed successfully",
]

print("Named Entity Recognition on Log Messages")
print("=" * 60)

for msg in log_messages:
    entities = ner(msg)
    print(f"\n  Log: {msg}")
    if entities:
        for ent in entities:
            print(f"    {ent['entity_group']:>5s}: '{ent['word']}' (confidence: {ent['score']:.2f})")
            # entity_group: PER (person), ORG (organization), LOC (location), MISC (other)
            # word: the actual text that was tagged
            # score: confidence level
    else:
        print("    No entities found")

print()
print("NER can extract structured data from unstructured log text")
print("Useful for: incident reports, audit logs, alert messages")
PYEOF
```

Expected output (yours will differ):

```
Named Entity Recognition on Log Messages
============================================================

  Log: Engineer John Smith restarted pg-primary-1 in us-east-1 at 3:45 AM
      PER: 'John Smith' (confidence: 0.99)
      LOC: 'us-east-1' (confidence: 0.72)

  Log: Microsoft Azure SQL instance db-prod-west failed health check
      ORG: 'Microsoft' (confidence: 0.99)
      MISC: 'Azure SQL' (confidence: 0.85)
```

---

## Step 6. Putting it all together - a practical example

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import pipeline
import time

print("""
Summary of HuggingFace pipelines:

TASK                    PIPELINE NAME              USE CASE
-----------------------------------------------------------------------
Sentiment analysis      "sentiment-analysis"       Classify alert severity
Zero-shot classify      "zero-shot-classification" Categorize without training
Text generation         "text-generation"          Generate docs, SQL
Feature extraction      (manual with AutoModel)    RAG, similarity search
Named entity recog.     "ner"                      Extract info from logs
Summarization           "summarization"            Summarize incident reports
Question answering      "question-answering"       Answer questions from docs
Fill-mask               "fill-mask"                Predict missing words
Translation             "translation"              Translate documentation

Key insight:
  ALL of these use the SAME Transformer architecture you learned.
  The only difference is:
    - Which model was used (BERT, GPT-2, BART, etc.)
    - How it was trained (classification, generation, etc.)
    - The final layer (classification head, generation head, etc.)

For real DBA work:
  - Sentiment/zero-shot: triage alerts automatically
  - Embeddings: power your RAG system (Module 03)
  - Generation: draft incident reports, documentation
  - NER: extract entities from logs and tickets

Next module (Module 09) teaches fine-tuning:
  Take a pre-trained model and specialize it for YOUR data.
""")
PYEOF
```

---

## What You Learned

| Pipeline | What It Does | DBA Use Case |
|----------|-------------|-------------|
| sentiment-analysis | Classifies text as positive/negative | Triage alert severity |
| zero-shot-classification | Classifies into any categories without training | Categorize alerts by type |
| text-generation | Generates text continuation | Draft documentation, SQL |
| Feature extraction (manual) | Converts text to embedding vectors | RAG, similarity search |
| ner | Finds names, locations, organizations in text | Extract info from logs |

**Key takeaway:** You don't need to build Transformers from scratch. HuggingFace gives you thousands of pre-trained models. But because you understand the internals (tokenization, attention, blocks), you can debug issues, choose the right model, and fine-tune effectively.
