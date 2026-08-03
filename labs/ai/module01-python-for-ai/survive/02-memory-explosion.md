# SURVIVE 02: The Memory Explosion

## Scenario

Your data pipeline processes server metrics every night. It's been running fine for months on a dataset of 100K rows. Last night it crashed with `MemoryError` because someone changed the input to 50 million rows. Your job: make it work without buying more RAM.

---

## The Broken Code

Save and run:

```bash
cat > /tmp/survive_memory.py << 'PYEOF'
import pandas as pd
import numpy as np
import time
import os

# Simulate a large dataset (we'll use 2M rows to avoid actually crashing your Mac)
print('Generating dataset...')
n = 2_000_000

start = time.time()

# THE SLOW WAY (how a beginner writes it)
results = []
for i in range(n):
    row = {
        'server_id': f'server-{i % 100:03d}',
        'cpu': np.random.normal(50, 20),
        'memory_gb': np.random.normal(8, 3),
        'disk_io': np.random.exponential(100),
        'timestamp': pd.Timestamp('2026-06-09') + pd.Timedelta(seconds=i)
    }
    results.append(row)

df = pd.DataFrame(results)

elapsed = time.time() - start
mem_mb = df.memory_usage(deep=True).sum() / 1024 / 1024
print(f'Time: {elapsed:.1f}s')
print(f'Memory: {mem_mb:.1f} MB')
print(f'Shape: {df.shape}')
print()

# Now do analysis
print('Computing stats...')
start2 = time.time()

# ANOTHER SLOW PATTERN: looping over rows
anomalies = []
for idx, row in df.iterrows():
    if row['cpu'] > 90 or row['memory_gb'] > 14:
        anomalies.append(idx)

print(f'Anomalies found: {len(anomalies)}')
print(f'Analysis time: {time.time() - start2:.1f}s')
PYEOF
python3 /tmp/survive_memory.py
```

This will take a long time and use too much memory. You might need to Ctrl+C after 30 seconds.

---

## Your Mission

Rewrite the script to:
1. Generate the same 2M row dataset in **under 2 seconds** (not 60+)
2. Use **less than 50 MB** of memory (not 200+)
3. Find anomalies in **under 1 second** (not 30+)
4. Produce the same results

**Rules:**
- Same columns, same data distributions
- Must print time and memory for comparison
- Must find the same type of anomalies (cpu > 90 or memory > 14)

---

## Diagnostic Steps

Before fixing, understand WHY it's slow:

```python
# Problem 1: Building a list of dicts then converting
#   - Each dict is a Python object (expensive)
#   - 2M dicts = 2M object allocations
#   - pd.DataFrame(list_of_dicts) copies everything AGAIN

# Problem 2: df.iterrows() loops in Python
#   - Python loops are ~100x slower than NumPy/Pandas vectorized ops
#   - iterrows() converts each row to a Series (memory overhead per row)
```

---

## Validation

After your fix, run your optimized script. It should print something like:

```
Time: <2s (was 60+s)
Memory: <50 MB (was 200+ MB)
Anomalies found: ~XXXX
Analysis time: <1s (was 30+s)
```

<details>
<summary>Runbook (hints, not answers)</summary>

1. **Don't build row by row.** Generate each column as a NumPy array first, then create the DataFrame from a dictionary of arrays. NumPy generates 2M random numbers in milliseconds.

2. **Use vectorized operations for filtering.** Instead of `for idx, row in df.iterrows()`, use: `df[(df['cpu'] > 90) | (df['memory_gb'] > 14)]` - this runs in C, not Python.

3. **Reduce memory with dtypes.**
   - `server_id` as a categorical column (100 unique values repeated 20K times each)
   - `float64` columns can often be `float32` (half the memory, plenty of precision)
   - Check with `df.memory_usage(deep=True)`

4. **For truly massive data (50M+ rows),** read in chunks: `pd.read_csv(file, chunksize=100000)` processes 100K rows at a time without loading everything.
</details>
