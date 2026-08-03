# Build 01: Feature Extraction from Multiple Data Types

Before you can combine text and metrics, you need to convert each into a consistent format - numbers. This is feature extraction.

---

## Python patterns used in this module

This module uses some Python patterns you'll see repeatedly. Here's a quick reference so you're not lost when they appear.

```
# --- f-strings ---
# f-strings let you put variables INSIDE a string.
# The f before the quotes means "format this string."
# Anything inside {} gets replaced with its value.
name = "postgres"
print(f"Database: {name}")     # prints: Database: postgres
# DBA analogy: like format() in PL/pgSQL or printf in bash.

# --- List comprehension ---
# A shortcut to build a list from a loop. Instead of:
#   result = []
#   for x in items:
#       if x > 5:
#           result.append(x)
# You write:
#   result = [x for x in items if x > 5]
# Read it as: "give me x, for each x in items, but only if x > 5"
# DBA analogy: like SELECT x FROM items WHERE x > 5.

# --- Dict comprehension ---
# Same idea but builds a dictionary instead of a list:
#   {key: value for key, value in items.items() if value > 0}
# Read it as: "give me key:value pairs, for each pair, if value > 0"
# DBA analogy: like SELECT key, value FROM items WHERE value > 0
#              but the result is a lookup table (dict).

# --- sum() with a generator ---
# sum(1 for x in items if x > 5)
# This COUNTS how many items match a condition.
# Read it as: "add 1 for each x in items where x > 5"
# DBA analogy: SELECT COUNT(*) FROM items WHERE x > 5.

# --- .get(key, default) ---
# Safe dictionary lookup. Returns the default if key doesn't exist.
# d.get("missing_key", 0) returns 0 instead of crashing.
# DBA analogy: like COALESCE(column, 0) in SQL.

# --- max(dict, key=dict.get) ---
# Find the dictionary key with the highest value.
# max({"a": 3, "b": 7, "c": 1}, key=scores.get) returns "b"
# DBA analogy: SELECT key FROM scores ORDER BY value DESC LIMIT 1.

# --- lambda ---
# A tiny one-line function without a name.
# lambda x: x[1] means "a function that takes x and returns x[1]"
# Used with sorted() or max() to tell them WHAT to sort/compare by.
# DBA analogy: like ORDER BY in SQL - you're telling it which column.

# --- zip() ---
# Pairs up items from two lists, like walking two lists side by side.
# zip([1, 2, 3], ["a", "b", "c"]) gives pairs: (1,"a"), (2,"b"), (3,"c")
# DBA analogy: like joining two arrays by position.

# --- enumerate() ---
# Gives you both the index AND the item when looping.
# for i, item in enumerate(["a", "b", "c"]):
#   prints: 0 a, 1 b, 2 c
# DBA analogy: like ROW_NUMBER() OVER() in a SELECT.

# --- tuple unpacking ---
# When a function returns two values, you can catch both:
# category, confidence = classify(text)
# This puts the first return value in 'category' and second in 'confidence'.
# DBA analogy: like SELECT col1, col2 INTO var1, var2.

# --- set() ---
# A collection with NO duplicates. Adding "cpu" twice still gives one "cpu".
# DBA analogy: like SELECT DISTINCT.

# --- try/except ---
# Run code that might fail, and handle the failure gracefully.
# try:
#     risky_thing()
# except SomeError as e:
#     print(f"Failed: {e}")
# DBA analogy: like BEGIN ... EXCEPTION WHEN ... in PL/pgSQL.
```

You don't need to memorize these now. Come back to this reference when you see a pattern you don't recognize.

---

## Step 1. Text feature extraction

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re                    # regex - for splitting text into words
import math                  # math functions - for log calculations
from collections import Counter  # Counter - counts how many times each item appears

# ============================================================
# TEXT FEATURE EXTRACTION
# Convert words into numbers the model can use.
#
# DBA analogy: text features are like extracting useful columns
# from a TEXT blob - you parse it into structured data.
# ============================================================

print("Text Feature Extraction")
print("=" * 50)

# --- Method 1: Keyword Features ---
# The simplest approach: check if specific keywords appear.
# Returns 1 if the word is found, 0 if not.
# Like a boolean column: has_keyword_disk = TRUE/FALSE.

def extract_keyword_features(text):
    """
    Check for important keywords in the text.
    Returns a dictionary of keyword: 0 or 1.

    DBA analogy: like creating boolean columns
    SELECT
      CASE WHEN message LIKE '%disk%' THEN 1 ELSE 0 END AS has_disk,
      CASE WHEN message LIKE '%cpu%' THEN 1 ELSE 0 END AS has_cpu
    FROM alerts;
    """
    text_lower = text.lower()          # convert to lowercase so "CPU" matches "cpu"

    # These are the keywords we care about, grouped by category
    keywords = [
        "cpu", "memory", "disk", "replication",
        "lag", "full", "slow", "error",
        "timeout", "connection", "ssl", "backup",
    ]

    features = {}                       # empty dict to store results
    for kw in keywords:                 # loop through each keyword
        # 1 if keyword is in the text, 0 if not
        features[f"has_{kw}"] = 1 if kw in text_lower else 0

    return features

# Test it
test_texts = [
    "CPU at 95% and memory usage high",
    "Disk full on /pgdata partition",
    "Replication lag 120 seconds on standby",
    "SSL certificate expires in 3 days",
]

print("\nMethod 1: Keyword Features")
print("-" * 50)
for text in test_texts:
    features = extract_keyword_features(text)
    # List comprehension: build a list of keyword names where the value is 1.
    # [k for k, v in features.items() if v == 1]
    #  ^           ^                     ^
    #  |           |                     +-- only include if value is 1
    #  |           +-- loop through each key-value pair
    #  +-- keep just the key (keyword name)
    # DBA analogy: SELECT key FROM features WHERE value = 1
    present = [k for k, v in features.items() if v == 1]
    print(f"  '{text[:40]}...'")
    print(f"    Keywords found: {present}")
    print()

# --- Method 2: Bag of Words ---
# Count how many times each word appears.
# More informative than just yes/no.

def extract_bow_features(text, vocabulary=None):
    """
    Bag of Words: count each word.

    DBA analogy: like GROUP BY word, COUNT(*)
    SELECT word, COUNT(*) FROM words GROUP BY word;
    """
    # Split text into words, keep only letters and numbers
    words = re.findall(r'[a-z0-9]+', text.lower())

    # Count each word
    word_counts = Counter(words)        # Counter({'cpu': 1, 'at': 1, '95': 1, ...})

    if vocabulary:
        # Dict comprehension: build a dictionary of {word: count} for known words.
        # .get(word, 0) returns 0 if the word wasn't found (like COALESCE in SQL).
        # DBA analogy: SELECT word, COALESCE(count, 0) FROM vocabulary LEFT JOIN word_counts
        return {word: word_counts.get(word, 0) for word in vocabulary}
    return dict(word_counts)

# Build a vocabulary from all our texts
# set() creates a collection that automatically removes duplicates.
# If you add "cpu" twice, the set still only has one "cpu".
# DBA analogy: like SELECT DISTINCT - no repeated values.
all_words = set()
for text in test_texts:
    words = re.findall(r'[a-z0-9]+', text.lower())
    all_words.update(words)             # add all words to the set

# Pick the most common words as our vocabulary
vocabulary = sorted(all_words)[:15]     # keep first 15 (alphabetical)

print("Method 2: Bag of Words")
print("-" * 50)
print(f"  Vocabulary (first 15): {vocabulary}")
for text in test_texts[:2]:             # show first 2 examples
    features = extract_bow_features(text, vocabulary)
    # Dict comprehension: keep only entries where count > 0
    # DBA analogy: SELECT key, value FROM features WHERE value > 0
    nonzero = {k: v for k, v in features.items() if v > 0}
    print(f"  '{text[:40]}...'")
    print(f"    Word counts: {nonzero}")
    print()

# --- Method 3: TF-IDF Features ---
# TF-IDF = Term Frequency * Inverse Document Frequency
# Words that appear in EVERY document are less useful (like "the", "on").
# Words that appear in FEW documents are more useful (like "replication", "ssl").

def compute_tfidf(texts, vocabulary):
    """
    TF-IDF: weight words by how unique they are.

    DBA analogy: common errors are less interesting than rare ones.
    An error that happens in every database is noise.
    An error in ONE database is a signal.
    """
    num_docs = len(texts)               # how many documents we have

    # Step 1: count how many documents contain each word
    doc_freq = Counter()                # how many docs have this word
    for text in texts:
        words_in_doc = set(re.findall(r'[a-z0-9]+', text.lower()))
        for word in words_in_doc:
            doc_freq[word] += 1         # this word appears in one more document

    results = []
    for text in texts:
        word_counts = Counter(re.findall(r'[a-z0-9]+', text.lower()))
        total_words = sum(word_counts.values())  # total words in this document

        tfidf = {}
        for word in vocabulary:
            # TF = how often this word appears in THIS document
            tf = word_counts.get(word, 0) / total_words if total_words > 0 else 0

            # IDF = log(total documents / documents containing this word)
            # Words in many docs get low IDF. Words in few docs get high IDF.
            df = doc_freq.get(word, 0)
            idf = math.log(num_docs / (1 + df))  # +1 to avoid dividing by zero

            tfidf[word] = round(tf * idf, 4)     # multiply TF * IDF

        results.append(tfidf)

    return results

print("Method 3: TF-IDF Features")
print("-" * 50)
tfidf_results = compute_tfidf(test_texts, vocabulary[:10])

# enumerate() gives you both the position number AND the item.
# So i=0, text="first alert" then i=1, text="second alert"
# DBA analogy: like ROW_NUMBER() OVER() - adds a counter to each row.
# [:2] means "take only the first 2 items" (like LIMIT 2 in SQL).
for i, text in enumerate(test_texts[:2]):
    scores = tfidf_results[i]
    # sorted() with key=lambda x: x[1] means "sort by the second element"
    # lambda x: x[1] is a tiny function: given x (a pair like ("word", 0.5)),
    # return x[1] (the number 0.5). So we're sorting by score.
    # reverse=True means highest first. [:5] means keep top 5.
    # DBA analogy: ORDER BY score DESC LIMIT 5
    top_words = sorted(scores.items(), key=lambda x: x[1], reverse=True)[:5]
    print(f"  '{text[:40]}...'")
    print(f"    Top TF-IDF words: {top_words}")
    print()

print("""
Summary: Three ways to convert text to numbers:
  1. Keyword features: simple yes/no (boolean columns)
  2. Bag of words: word counts (GROUP BY + COUNT)
  3. TF-IDF: weighted by uniqueness (rare words score higher)
""")
PYEOF
```

---

## Step 2. Numeric feature extraction

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import math   # for log function

# ============================================================
# NUMERIC FEATURE EXTRACTION
# Normalize metrics so they're on the same scale.
#
# DBA analogy: CPU is 0-100, disk is 0-10TB, connections 0-500.
# You can't compare them directly. Normalize first.
# Like normalizing a database - consistent format.
# ============================================================

print("Numeric Feature Extraction")
print("=" * 50)

# --- Method 1: Min-Max Scaling ---
# Squeeze any range into 0-1.
# Formula: (value - min) / (max - min)
# 0 = the lowest value, 1 = the highest value.

def min_max_scale(values):
    """
    Scale values to 0-1 range.

    DBA analogy: like normalizing percentages.
    CPU is already 0-100, but connections might be 0-500.
    After scaling, both are 0.0 to 1.0.
    """
    min_val = min(values)               # find the smallest value
    max_val = max(values)               # find the largest value
    range_val = max_val - min_val       # the spread

    if range_val == 0:                  # all values are the same
        return [0.0] * len(values)      # return all zeros

    # Scale each value: subtract min, divide by range
    scaled = []
    for v in values:
        scaled_value = (v - min_val) / range_val
        scaled.append(round(scaled_value, 4))

    return scaled

# Test with different metric ranges
cpu_values = [25, 50, 75, 95, 100]
disk_bytes = [100_000, 500_000, 1_000_000, 5_000_000, 10_000_000]
connections = [10, 50, 100, 200, 500]

print("\nMethod 1: Min-Max Scaling (squeeze to 0-1)")
print("-" * 50)
print(f"  CPU values:    {cpu_values}")
print(f"  CPU scaled:    {min_max_scale(cpu_values)}")
print(f"  Disk bytes:    {disk_bytes}")
print(f"  Disk scaled:   {min_max_scale(disk_bytes)}")
print(f"  Connections:   {connections}")
print(f"  Conn scaled:   {min_max_scale(connections)}")

# --- Method 2: Standard Scaling (Z-score) ---
# Center around 0, measure in standard deviations.
# Formula: (value - mean) / std_dev
# After scaling: mean=0, std=1.
# Values > 0 are above average, < 0 are below average.

def standard_scale(values):
    """
    Z-score scaling: center at 0, spread by standard deviation.

    DBA analogy: like measuring how far a metric is from normal.
    CPU at z=2.5 means "2.5 standard deviations above average" = very high.
    """
    n = len(values)
    mean = sum(values) / n              # average

    # Standard deviation: average distance from the mean
    variance = sum((v - mean) ** 2 for v in values) / n
    std_dev = variance ** 0.5           # square root of variance

    if std_dev == 0:                    # all values are the same
        return [0.0] * n

    scaled = []
    for v in values:
        z_score = (v - mean) / std_dev  # how many std devs from mean
        scaled.append(round(z_score, 4))

    return scaled

print("\nMethod 2: Standard Scaling (Z-score)")
print("-" * 50)
print(f"  CPU values:    {cpu_values}")
print(f"  CPU z-scores:  {standard_scale(cpu_values)}")
print(f"  Connections:   {connections}")
print(f"  Conn z-scores: {standard_scale(connections)}")

# --- Method 3: Log Scaling ---
# For values with huge range (bytes: 0 to terabytes).
# log() compresses big numbers more than small numbers.

def log_scale(values):
    """
    Log scaling: compress huge ranges.

    DBA analogy: database sizes range from 1MB to 10TB.
    log(1MB)=6, log(1GB)=9, log(1TB)=12. Much more manageable.
    """
    scaled = []
    for v in values:
        # math.log(v + 1) because log(0) is undefined
        # +1 ensures we can handle zero values
        log_val = math.log(v + 1)
        scaled.append(round(log_val, 4))
    return scaled

print("\nMethod 3: Log Scaling (compress big ranges)")
print("-" * 50)
print(f"  Disk bytes:    {disk_bytes}")
print(f"  Disk log:      {log_scale(disk_bytes)}")
print(f"  After min-max: {min_max_scale(log_scale(disk_bytes))}")

print("""
Summary: Three ways to normalize numbers:
  1. Min-Max: squeeze to 0-1 (good for bounded metrics like CPU %)
  2. Z-score: center at 0, unit = std dev (good for detecting outliers)
  3. Log: compress huge ranges (good for bytes, counts, latencies)

Which to use:
  CPU percentage (0-100)     -> min-max scaling
  Database size (bytes)      -> log scaling then min-max
  Query latency (ms)         -> log scaling (range: 0.1ms to 30s)
  Connection count           -> min-max or z-score
""")
PYEOF
```

---

## Step 3. Combined feature extractor

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import re
import math
from collections import Counter

# ============================================================
# COMBINED FEATURE EXTRACTOR
# One class that handles both text and numeric data.
#
# DBA analogy: like a VIEW that joins the text alert table
# with the metrics table - giving you one unified row per alert.
# ============================================================

print("Combined Feature Extractor")
print("=" * 50)

class FeatureExtractor:
    """
    Extract features from both text and numeric data.

    DBA analogy: this is a VIEW that joins alerts + metrics
    into one row with all the columns you need for analysis.

    CREATE VIEW alert_features AS
    SELECT a.message, a.has_disk, a.has_cpu,
           m.cpu_pct_scaled, m.disk_pct_scaled
    FROM alert_text_features a
    JOIN metric_features m ON a.alert_id = m.alert_id;
    """

    def __init__(self):
        # Keywords to look for in text
        self.keywords = [
            "cpu", "memory", "disk", "replication",
            "lag", "full", "slow", "error",
            "timeout", "connection",
        ]

        # Expected ranges for numeric metrics (for min-max scaling)
        # format: metric_name -> (min_value, max_value)
        self.metric_ranges = {
            "cpu_percent": (0, 100),
            "memory_percent": (0, 100),
            "disk_percent": (0, 100),
            "connections": (0, 500),
            "replication_lag_seconds": (0, 3600),
            "query_latency_ms": (0, 30000),
        }

    def extract_text_features(self, text):
        """Extract keyword features from text."""
        text_lower = text.lower()
        features = {}
        for kw in self.keywords:
            features[f"text_{kw}"] = 1 if kw in text_lower else 0

        # Also extract: word count and average word length
        words = re.findall(r'[a-z0-9]+', text_lower)
        features["text_word_count"] = len(words)
        if words:
            features["text_avg_word_len"] = round(
                sum(len(w) for w in words) / len(words), 2
            )
        else:
            features["text_avg_word_len"] = 0

        return features

    def extract_numeric_features(self, metrics):
        """
        Extract and scale numeric features.

        metrics: dict like {"cpu_percent": 95, "disk_percent": 42}
        """
        features = {}
        for metric_name, (min_val, max_val) in self.metric_ranges.items():
            value = metrics.get(metric_name)         # get the value, might be None

            if value is not None:
                # Min-max scale using known ranges
                range_val = max_val - min_val
                if range_val > 0:
                    scaled = (value - min_val) / range_val
                    scaled = max(0.0, min(1.0, scaled))  # clamp to 0-1
                else:
                    scaled = 0.0
                features[f"metric_{metric_name}"] = round(scaled, 4)
                features[f"metric_{metric_name}_missing"] = 0  # not missing
            else:
                # Missing metric - use 0 and flag it
                features[f"metric_{metric_name}"] = 0.0
                features[f"metric_{metric_name}_missing"] = 1  # is missing

        return features

    def extract(self, text, metrics):
        """
        Extract ALL features from both text and metrics.
        Returns one combined feature dictionary.

        DBA analogy: this is the final SELECT that joins everything.
        """
        text_features = self.extract_text_features(text)
        numeric_features = self.extract_numeric_features(metrics)

        # Combine into one dictionary
        combined = {}
        combined.update(text_features)       # add all text features
        combined.update(numeric_features)    # add all numeric features

        return combined

# Test it
extractor = FeatureExtractor()

test_alerts = [
    {
        "text": "CPU at 95% - queries running slow",
        "metrics": {"cpu_percent": 95, "memory_percent": 60, "connections": 150},
    },
    {
        "text": "Disk full on /pgdata",
        "metrics": {"disk_percent": 98, "cpu_percent": 30},
    },
    {
        "text": "Replication lag 120 seconds on standby",
        "metrics": {"replication_lag_seconds": 120, "cpu_percent": 45},
    },
    {
        "text": "Connection timeout from app server",
        "metrics": {"connections": 490, "cpu_percent": 80},
    },
]

print("\nCombined Features for Each Alert:")
print("-" * 50)

for alert in test_alerts:
    features = extractor.extract(alert["text"], alert["metrics"])

    # Show non-zero text features
    text_feats = {k: v for k, v in features.items()
                  if k.startswith("text_") and v != 0 and "word" not in k}
    # Show non-zero, non-missing metric features
    metric_feats = {k: v for k, v in features.items()
                    if k.startswith("metric_") and v != 0 and "missing" not in k}

    print(f"  Alert: '{alert['text'][:45]}'")
    print(f"    Text features:   {text_feats}")
    print(f"    Metric features: {metric_feats}")
    print(f"    Total features:  {len(features)}")
    print()

# Count feature types
sample = extractor.extract("test", {})
text_count = sum(1 for k in sample if k.startswith("text_"))
metric_count = sum(1 for k in sample if k.startswith("metric_"))
print(f"Feature breakdown: {text_count} text + {metric_count} metric = {len(sample)} total")

print("""
What we built:
  1. Text features: keyword presence (0/1) + word stats
  2. Numeric features: scaled metrics (0-1) + missing flags
  3. Combined extractor: one function call gets everything

Next: we'll use these combined features for classification.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Keyword features | Binary flags for important words | CASE WHEN LIKE '%keyword%' |
| Bag of words | Count word frequencies | GROUP BY word, COUNT(*) |
| TF-IDF | Weight words by uniqueness | Rare errors are more interesting |
| Min-max scaling | Squeeze numbers to 0-1 | Normalize different metric ranges |
| Z-score scaling | Measure distance from average | How far from normal? |
| Log scaling | Compress huge ranges | Database sizes: MB to TB |
| Missing flags | Track which data is absent | LEFT JOIN with IS NULL check |
| Combined extractor | One function for all features | VIEW joining text + metrics |
