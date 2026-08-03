# SURVIVE 02: Context Window Overflow

Your application sends a long prompt to the model and gets garbage output - or an error. The input exceeded the model's context window (maximum token limit). You need to handle this without losing important information.

---

## The Scenario

A DBA built a system that sends full PostgreSQL log files to a Transformer model for analysis. Works fine with small logs (100 lines). But production logs are 50,000+ lines. The model either truncates silently (missing the important error at the end) or crashes with an error.

---

## Step 1. See the problem

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import AutoTokenizer

# Different models have different context windows
models = {
    "gpt2": 1024,              # 1K tokens
    "bert-base-uncased": 512,   # 512 tokens
    "distilbert-base-uncased": 512,
}

print("Model Context Window Limits:")
print("=" * 50)
for model_name, max_tokens in models.items():
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    print(f"  {model_name:30s}  {max_tokens:>6,} tokens")

print()
print("  GPT-3.5-turbo                    4,096 tokens")
print("  GPT-4                          128,000 tokens")
print("  Claude 3.5 Sonnet              200,000 tokens")
print("  Claude 4 Opus                  200,000 tokens")
print()

# Simulate a database log
log_lines = []
for i in range(1000):
    log_lines.append(f"2024-01-15 10:00:{i:03d} LOG: connection received: host=10.0.0.{i%255}")
# List of 1000 log lines simulating PostgreSQL connection logs
# f-string formats: :03d = pad to 3 digits, %255 = wrap IP to valid range

# Add the critical error at the END (common in real logs)
log_lines.append("2024-01-15 10:15:00 ERROR: could not write to WAL: No space left on device")
log_lines.append("2024-01-15 10:15:01 FATAL: the database system is shutting down")

full_log = "\n".join(log_lines)
# "\n".join() combines all lines with newlines between them

# Tokenize the full log
tokenizer = AutoTokenizer.from_pretrained("gpt2")
tokens = tokenizer.encode(full_log)

print(f"Log: {len(log_lines)} lines, {len(full_log):,} characters")
print(f"Token count: {len(tokens):,} tokens")
print(f"GPT-2 max: 1,024 tokens")
print()

if len(tokens) > 1024:
    # If we truncate to fit the context window...
    truncated_tokens = tokens[:1024]
    truncated_text = tokenizer.decode(truncated_tokens)
    # decode() converts token IDs back to text
    truncated_lines = truncated_text.count("\n")
    print(f"If truncated to 1024 tokens: only {truncated_lines} lines fit")
    print(f"The CRITICAL error at the end? LOST.")
    print()
    print("Last line of truncated text:")
    last_line = truncated_text.strip().split("\n")[-1]
    # .strip() removes whitespace, .split("\n") splits by newlines, [-1] gets last
    print(f"  {last_line}")
    print()
    print("The ERROR and FATAL messages at the end are gone!")
    print("This is how silent truncation causes missed incidents.")
PYEOF
```

Expected output (yours will differ):

```
Log: 1002 lines, 78,156 characters
Token count: 21,342 tokens
GPT-2 max: 1,024 tokens

If truncated to 1024 tokens: only 43 lines fit
The CRITICAL error at the end? LOST.

Last line of truncated text:
  2024-01-15 10:00:043 LOG: connection received: host=10.0.0.43

The ERROR and FATAL messages at the end are gone!
```

---

## Step 2. The fixes

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("gpt2")

# Simulate log with error at the end
log_lines = [f"2024-01-15 10:00:{i:03d} LOG: connection received: host=10.0.0.{i%255}"
             for i in range(1000)]
log_lines.append("2024-01-15 10:15:00 ERROR: could not write to WAL: No space left on device")
log_lines.append("2024-01-15 10:15:01 FATAL: the database system is shutting down")

print("=" * 60)
print("FIX 1: Smart Truncation (keep start AND end)")
print("=" * 60)

def smart_truncate(text, max_tokens=1024, tokenizer=tokenizer):
    """Keep the first and last portions, skip the middle."""
    tokens = tokenizer.encode(text)
    if len(tokens) <= max_tokens:
        return text  # fits already, no truncation needed

    # Keep first 30% and last 70% (errors are usually at the end)
    first_n = int(max_tokens * 0.3)   # 307 tokens from start
    last_n = max_tokens - first_n      # 717 tokens from end

    truncated = tokens[:first_n] + tokens[-last_n:]
    # tokens[:first_n] = first 307 tokens
    # tokens[-last_n:] = last 717 tokens
    # Concatenate them with the middle removed

    return tokenizer.decode(truncated)

full_log = "\n".join(log_lines)
truncated = smart_truncate(full_log)

# Check if the error is preserved
has_error = "No space left on device" in truncated
has_fatal = "shutting down" in truncated
print(f"  Contains ERROR line: {has_error}")
print(f"  Contains FATAL line: {has_fatal}")
print(f"  Token count: {len(tokenizer.encode(truncated))}")
print()

print("=" * 60)
print("FIX 2: Filter Before Tokenizing")
print("=" * 60)

def filter_log(lines, keywords=None):
    """Keep only lines matching important keywords."""
    if keywords is None:
        keywords = ["ERROR", "FATAL", "WARNING", "PANIC", "CRITICAL"]
        # These are the PostgreSQL log levels that indicate problems
    filtered = [line for line in lines if any(kw in line for kw in keywords)]
    # List comprehension: keep line if ANY keyword appears in it
    # any() returns True if at least one element is True
    return filtered

filtered = filter_log(log_lines)
filtered_text = "\n".join(filtered)
filtered_tokens = len(tokenizer.encode(filtered_text))

print(f"  Original: {len(log_lines)} lines, {len(tokenizer.encode(full_log)):,} tokens")
print(f"  Filtered: {len(filtered)} lines, {filtered_tokens} tokens")
print(f"  Filtered lines:")
for line in filtered:
    print(f"    {line}")
print()

print("=" * 60)
print("FIX 3: Chunking (split into pieces, process each)")
print("=" * 60)

def chunk_text(text, max_tokens=1024, overlap=100, tokenizer=tokenizer):
    """Split text into overlapping chunks that fit the context window."""
    tokens = tokenizer.encode(text)
    chunks = []
    start = 0
    while start < len(tokens):
        end = start + max_tokens
        chunk_tokens = tokens[start:end]
        chunks.append(tokenizer.decode(chunk_tokens))
        start = end - overlap
        # overlap: each chunk shares some tokens with the next
        # This prevents cutting in the middle of important context
    return chunks

chunks = chunk_text(full_log, max_tokens=1024, overlap=100)
print(f"  Full log: {len(tokenizer.encode(full_log)):,} tokens")
print(f"  Split into: {len(chunks)} chunks of ~1024 tokens each")
print(f"  Overlap: 100 tokens between chunks")
print()
print("  Process each chunk separately, then combine results")
print("  The last chunk contains the ERROR and FATAL lines")

# Verify
last_chunk = chunks[-1]
print(f"\n  Last chunk contains ERROR: {'ERROR' in last_chunk}")
print(f"  Last chunk contains FATAL: {'FATAL' in last_chunk}")
PYEOF
```

Expected output (yours will differ):

```
FIX 1: Smart Truncation (keep start AND end)
  Contains ERROR line: True
  Contains FATAL line: True
  Token count: 1024

FIX 2: Filter Before Tokenizing
  Original: 1002 lines, 21,342 tokens
  Filtered: 2 lines, 32 tokens
  Filtered lines:
    2024-01-15 10:15:00 ERROR: could not write to WAL: No space left on device
    2024-01-15 10:15:01 FATAL: the database system is shutting down

FIX 3: Chunking (split into pieces, process each)
  Full log: 21,342 tokens
  Split into: 22 chunks of ~1024 tokens each
```

---

## Step 3. Prevention checklist

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Context Window Overflow - Prevention Checklist:

1. ALWAYS check token count before sending to a model
   tokens = tokenizer.encode(text)
   if len(tokens) > model_max:
       # handle it

2. Choose the right strategy:

   STRATEGY         WHEN TO USE                   TRADE-OFF
   ---------------------------------------------------------------
   Smart truncate   Need start AND end context    Loses middle
   Filter first     Know what's important          May miss context
   Chunking         Need to process everything     Slower, costs more
   Summarize first  Long documents, need overview  Loses detail

3. For database logs specifically:
   - Filter by severity (ERROR, FATAL, WARNING) FIRST
   - If still too long, use smart truncation (keep end)
   - Never truncate from the end - errors are usually at the end

4. For production systems:
   - Set max_length in tokenizer: tokenizer(text, max_length=512, truncation=True)
   - Log a warning when truncation happens
   - Monitor token counts in your metrics

5. Know your model's limit:
   - BERT/DistilBERT: 512 tokens
   - GPT-2: 1,024 tokens
   - GPT-4: 128,000 tokens
   - Claude: 200,000 tokens
   - Even 200K tokens has a limit - a full pg_dump can exceed it
""")
PYEOF
```

---

## What You Learned

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Send full log to model | Silent truncation, missed errors | Filter by severity first |
| Truncate from start only | Critical errors at end are lost | Smart truncate (keep start + end) |
| No token count check | Random failures on large inputs | Always check before sending |
| One huge prompt | Exceeds context window | Chunk with overlap |
