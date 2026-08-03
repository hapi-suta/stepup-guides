# Build 04: Preparing Training Data

Your fine-tuned model is only as good as your training data. This guide covers data formatting, quality checks, augmentation, and the common mistakes that ruin fine-tuning.

---

## Step 1. Data format for fine-tuning

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json

print("""
Fine-tuning data formats depend on your task:

1. CLASSIFICATION (most common for DBAs):
   {"text": "CPU usage exceeded 95%", "label": "performance"}
   {"text": "Disk full on /pgdata", "label": "storage"}

2. GENERATION / CHAT (for API fine-tuning):
   {"messages": [
     {"role": "system", "content": "You are a database assistant"},
     {"role": "user", "content": "What causes replication lag?"},
     {"role": "assistant", "content": "Common causes include..."}
   ]}

3. INSTRUCTION FOLLOWING:
   {"instruction": "Classify this alert", "input": "CPU at 95%", "output": "performance"}

4. TEXT PAIRS (for similarity/embedding):
   {"text1": "server is slow", "text2": "high latency detected", "label": 1}
""")

# Create a proper JSONL dataset (JSON Lines format)
# Each line is one JSON object - the standard format for fine-tuning

dataset = [
    {"text": "CPU usage on pg-primary-1 exceeded 95% for 10 minutes", "label": "performance"},
    {"text": "Query took 45 seconds to complete on orders table", "label": "performance"},
    {"text": "Disk usage on /pgdata reached 92% capacity", "label": "storage"},
    {"text": "WAL directory growing at 500MB per hour", "label": "storage"},
    {"text": "Replication lag reached 120 seconds on standby", "label": "replication"},
    {"text": "Streaming replication connection lost", "label": "replication"},
    {"text": "Failed login attempt from unknown IP address", "label": "security"},
    {"text": "Unauthorized DROP TABLE attempt blocked", "label": "security"},
]

# Write to JSONL file
output_path = "/tmp/alerts_train.jsonl"
with open(output_path, "w") as f:
    for item in dataset:
        f.write(json.dumps(item) + "\n")
        # json.dumps() converts dictionary to JSON string
        # Each example is one line (JSONL = JSON Lines)

print(f"Saved {len(dataset)} examples to {output_path}")
print()

# Read it back (verify)
with open(output_path) as f:
    loaded = [json.loads(line) for line in f]
    # json.loads() parses JSON string back to dictionary
    # List comprehension: do this for every line

print(f"Loaded {len(loaded)} examples")
print(f"First example: {loaded[0]}")
print(f"Format: JSONL (one JSON object per line)")
PYEOF
```

---

## Step 2. Data quality checks

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
from collections import Counter

# Expanded dataset with intentional quality issues
dataset = [
    # Good examples
    {"text": "CPU usage on pg-primary-1 exceeded 95% for 10 minutes", "label": "performance"},
    {"text": "Slow query detected: sequential scan returned 1M rows", "label": "performance"},
    {"text": "Average query latency increased from 5ms to 250ms", "label": "performance"},
    {"text": "Connection pool exhausted - 100/100 connections", "label": "performance"},
    {"text": "Disk usage on /pgdata reached 92% capacity", "label": "storage"},
    {"text": "WAL directory growing at 500MB per hour", "label": "storage"},
    {"text": "Table bloat on orders exceeds 40%", "label": "storage"},
    {"text": "Replication lag reached 120 seconds", "label": "replication"},
    {"text": "Streaming replication connection lost", "label": "replication"},
    {"text": "WAL sender process terminated", "label": "replication"},
    {"text": "Failed login from unknown IP 203.0.113.42", "label": "security"},
    {"text": "Unauthorized DROP TABLE attempt blocked", "label": "security"},

    # BAD examples (intentional quality issues)
    {"text": "", "label": "performance"},                    # empty text
    {"text": "CPU high", "label": "performance"},            # too short
    {"text": "Disk full", "label": "performance"},           # WRONG label (should be storage)
    {"text": "Disk usage on /pgdata reached 92% capacity", "label": "storage"},  # duplicate
    {"text": None, "label": "security"},                     # null text
]

print("Data Quality Checks")
print("=" * 60)

issues = []

# Check 1: Empty or null texts
empty_count = sum(1 for d in dataset if not d.get("text"))
# d.get("text") returns None if key missing, then "not None" = True for empty/null
if empty_count > 0:
    issues.append(f"  FAIL: {empty_count} empty/null texts found")
    print(f"  [X] Empty texts: {empty_count} found")
else:
    print(f"  [OK] No empty texts")

# Check 2: Very short texts (likely low quality)
short_count = sum(1 for d in dataset if d.get("text") and len(d["text"]) < 10)
if short_count > 0:
    issues.append(f"  FAIL: {short_count} texts shorter than 10 chars")
    print(f"  [X] Short texts (<10 chars): {short_count} found")
else:
    print(f"  [OK] No very short texts")

# Check 3: Duplicate texts
texts_only = [d["text"] for d in dataset if d.get("text")]
text_counts = Counter(texts_only)
# Counter counts occurrences of each unique text
duplicates = {t: c for t, c in text_counts.items() if c > 1}
# Dictionary comprehension: keep only texts that appear more than once
if duplicates:
    issues.append(f"  FAIL: {len(duplicates)} duplicate texts")
    print(f"  [X] Duplicates: {len(duplicates)} texts appear more than once")
    for text, count in duplicates.items():
        print(f"      '{text[:50]}...' appears {count}x")
else:
    print(f"  [OK] No duplicate texts")

# Check 4: Label distribution (should be balanced)
valid_data = [d for d in dataset if d.get("text") and len(d["text"]) >= 10]
label_counts = Counter(d["label"] for d in valid_data)
print(f"\n  Label distribution:")
for label, count in sorted(label_counts.items()):
    bar = "#" * (count * 3)  # visual bar
    print(f"    {label:>15s}: {count:>3d}  {bar}")

max_count = max(label_counts.values())
min_count = min(label_counts.values())
ratio = max_count / min_count if min_count > 0 else float('inf')
if ratio > 3:
    issues.append(f"  WARN: Label imbalance ratio {ratio:.1f}x")
    print(f"  [X] Imbalanced: {ratio:.1f}x ratio (max {max_count} vs min {min_count})")
else:
    print(f"  [OK] Balanced: {ratio:.1f}x ratio")

# Summary
print()
if issues:
    print(f"Found {len(issues)} issues:")
    for issue in issues:
        print(issue)
    print()
    print("Fix these BEFORE fine-tuning! Bad data = bad model.")
else:
    print("All checks passed!")

# Clean the dataset
print()
print("Cleaning dataset...")
clean_data = []
seen_texts = set()  # set() stores unique values for fast lookup

for d in dataset:
    text = d.get("text")
    if not text or len(text) < 10:
        continue  # skip empty and short texts
    if text in seen_texts:
        continue  # skip duplicates
    seen_texts.add(text)
    clean_data.append(d)

print(f"  Before cleaning: {len(dataset)} examples")
print(f"  After cleaning:  {len(clean_data)} examples")
print(f"  Removed: {len(dataset) - len(clean_data)} bad examples")
PYEOF
```

Expected output (yours will differ):

```
Data Quality Checks
============================================================
  [X] Empty texts: 2 found
  [X] Short texts (<10 chars): 1 found
  [X] Duplicates: 1 texts appear more than once

  Label distribution:
    performance:   4  ############
    replication:   3  #########
       security:   1  ###
        storage:   3  #########
  [X] Imbalanced: 4.0x ratio

Found 4 issues:
  ...
```

---

## Step 3. Data augmentation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import random
random.seed(42)

print("""
Data Augmentation: Create MORE training examples from existing ones.

When you only have 50-200 examples (common for DBA tasks),
augmentation can double or triple your dataset.

Techniques:
  1. Synonym replacement: swap words with similar meanings
  2. Random deletion: remove random words
  3. Template variation: same meaning, different wording
  4. Back-translation: translate to another language and back (not shown)
""")

# Original examples
originals = [
    ("CPU usage exceeded 95% on the primary server", "performance"),
    ("Disk space is running low on /pgdata volume", "storage"),
    ("Replication lag increased to 60 seconds", "replication"),
    ("Unauthorized access attempt from external IP", "security"),
]

# Technique 1: Synonym replacement
synonyms = {
    "exceeded": ["surpassed", "went above", "reached beyond"],
    "running low": ["nearly full", "almost exhausted", "critically low"],
    "increased": ["grew", "jumped", "spiked"],
    "unauthorized": ["illegitimate", "forbidden", "blocked"],
    "server": ["host", "instance", "node"],
    "attempt": ["request", "connection", "access"],
}

def synonym_replace(text):
    """Replace random words with synonyms."""
    for word, syns in synonyms.items():
        if word in text:
            replacement = random.choice(syns)
            # random.choice picks one random item from the list
            text = text.replace(word, replacement, 1)
            # .replace(old, new, 1) replaces only the first occurrence
            break  # only replace one word per augmentation
    return text

# Technique 2: Random word deletion
def random_delete(text, p=0.1):
    """Delete each word with probability p."""
    words = text.split()
    # .split() breaks text into words by whitespace
    if len(words) <= 3:
        return text  # don't delete from very short texts
    kept = [w for w in words if random.random() > p]
    # random.random() returns float between 0 and 1
    # Keep word if random number > p (90% chance for p=0.1)
    return " ".join(kept)
    # " ".join() combines words back into a string with spaces

# Technique 3: Template variations
templates = {
    "performance": [
        "{metric} is at {value} on {server}",
        "Alert: {metric} threshold breached on {server}",
        "High {metric} detected: {value} on {server}",
    ],
    "storage": [
        "Disk usage at {pct}% on {path}",
        "Storage alert: {path} is {pct}% full",
        "{path} running low on space ({pct}% used)",
    ],
}

# Generate augmented data
augmented = []

for text, label in originals:
    augmented.append((text, label))  # keep original

    # Add synonym variations
    for _ in range(2):
        aug = synonym_replace(text)
        if aug != text:
            augmented.append((aug, label))

    # Add deletion variations
    for _ in range(2):
        aug = random_delete(text)
        if aug != text:
            augmented.append((aug, label))

print(f"Original examples: {len(originals)}")
print(f"After augmentation: {len(augmented)}")
print(f"Increase: {len(augmented)/len(originals):.1f}x")
print()

print("Sample augmented data:")
print("-" * 70)
for text, label in augmented[:12]:
    print(f"  [{label:>13s}] {text}")

print()
print("IMPORTANT: Augmentation should NOT change the meaning.")
print("If 'CPU exceeded 95%' becomes 'CPU exceeded 5%', that's wrong!")
print("Always review augmented data before training.")
PYEOF
```

Expected output (yours will differ):

```
Original examples: 4
After augmentation: 16
Increase: 4.0x

Sample augmented data:
----------------------------------------------------------------------
  [  performance] CPU usage exceeded 95% on the primary server
  [  performance] CPU usage surpassed 95% on the primary server
  [  performance] CPU usage exceeded 95% on the primary host
  ...
```

---

## Step 4. The complete data preparation pipeline

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json

print("""
Complete Data Preparation Pipeline for Fine-Tuning:

STEP 1: Collect raw data
  - Export from your ticketing system (Jira, PagerDuty, etc.)
  - Pull from alert history (Prometheus, Grafana, etc.)
  - Extract from log files (PostgreSQL logs, syslogs)

STEP 2: Label the data
  - Manual labeling: you or your team reads each example and assigns a category
  - Semi-automatic: use zero-shot classification (Module 08) to pre-label,
    then manually review and correct
  - Minimum: 100 examples per category, ideally 500+

STEP 3: Clean the data
  - Remove duplicates
  - Remove empty/null entries
  - Fix mislabeled examples (most impactful step!)
  - Standardize text format (lowercase? strip whitespace?)

STEP 4: Augment (if needed)
  - Only if you have < 200 examples per category
  - Synonym replacement, template variation, deletion
  - Review augmented examples for correctness

STEP 5: Split the data
  - Train: 80% (model learns from this)
  - Validation: 10% (tune hyperparameters against this)
  - Test: 10% (final evaluation, only used once)
  - NEVER let test data leak into training

STEP 6: Format for your framework
  - HuggingFace: JSONL with "text" and "label" fields
  - OpenAI: JSONL with "messages" array
  - PyTorch: CSV or JSONL, loaded into DataLoader

STEP 7: Version your data
  - Save with date: alerts_train_2024_01_15.jsonl
  - Track changes: what was added, removed, relabeled
  - Keep test set FIXED across experiments
  - If you change the test set, you can't compare results

Common Mistakes:
  1. Too few examples (< 50 per category) -> model doesn't learn
  2. Mislabeled data (10%+ wrong labels) -> model learns wrong patterns
  3. Duplicate texts with different labels -> model gets confused
  4. Imbalanced classes (1000 vs 10) -> model ignores minority class
  5. Test data in training set -> artificially inflated metrics
  6. Not shuffling before split -> all categories clustered together
""")
PYEOF
```

---

## What You Learned

| Step | What | Why |
|------|------|-----|
| JSONL format | One JSON object per line | Standard format for fine-tuning |
| Quality checks | Find empty, short, duplicate, mislabeled data | Bad data = bad model, always check first |
| Label balance | Equal examples per category | Imbalanced data biases the model |
| Augmentation | Create more examples from existing ones | More data improves model quality |
| Data pipeline | Collect, label, clean, augment, split, format | Systematic process prevents mistakes |
| Version data | Track changes, keep test set fixed | Reproducibility and fair comparison |
