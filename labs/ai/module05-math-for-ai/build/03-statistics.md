# Build 03: Statistics - Measuring Your Data

Statistics tells you what your data looks like. You already use statistics as a DBA - `avg()`, `count()`, `stddev()`. AI uses the exact same concepts to evaluate models and understand data.

---

## Step 1. Mean, median, and mode - the basics

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# Query response times (milliseconds) from 20 queries
# Some are fast, some are slow, one is REALLY slow
query_times = np.array([
    12, 15, 11, 14, 13, 16, 12, 14, 15, 11,
    13, 14, 12, 15, 13, 14, 11, 12, 500, 14
])
#                                     ^^^
#                       This one query took 500ms (outlier!)

print(f"Query times: {query_times}")
print(f"Number of queries: {len(query_times)}")
print()

# --- Mean (average) ---
# Add up all values, divide by count
# Same as SQL: SELECT avg(query_time) FROM pg_stat_statements;
mean = np.mean(query_times)
print(f"Mean (average): {mean:.1f} ms")
print("  Problem: the 500ms outlier pulls the average up!")
print()

# --- Median (middle value) ---
# Sort the values, pick the one in the middle
# Not affected by outliers - much more useful for skewed data
# Same as SQL: percentile_cont(0.5) WITHIN GROUP (ORDER BY query_time)
median = np.median(query_times)
print(f"Median (middle value): {median:.1f} ms")
print("  Much better! The median ignores that one slow query.")
print()

# --- Min and Max ---
print(f"Min: {np.min(query_times)} ms")
print(f"Max: {np.max(query_times)} ms")
print(f"Range: {np.max(query_times) - np.min(query_times)} ms")
print()

# --- Percentiles ---
# "What value is X% of the data below?"
# p50 = median, p95 = 95th percentile, p99 = 99th percentile
# Same as SQL: percentile_cont(0.95) WITHIN GROUP (ORDER BY query_time)
p50 = np.percentile(query_times, 50)
p95 = np.percentile(query_times, 95)
p99 = np.percentile(query_times, 99)
print(f"p50 (median):  {p50:.1f} ms")
print(f"p95:           {p95:.1f} ms  <- 95% of queries are faster than this")
print(f"p99:           {p99:.1f} ms  <- 99% of queries are faster than this")
print()

print("In AI, you'll use these to check:")
print("  - Mean loss: is the model getting better? (should decrease)")
print("  - Median accuracy: typical model performance")
print("  - p99 latency: worst-case inference time")
PYEOF
```

Expected output (yours will differ):
```
Query times: [ 12  15  11  14  13  16  12  14  15  11  13  14  12  15  13  14  11  12 500  14]
Number of queries: 20

Mean (average): 37.3 ms
  Problem: the 500ms outlier pulls the average up!

Median (middle value): 13.5 ms
  Much better! The median ignores that one slow query.

Min: 11 ms
Max: 500 ms
Range: 489 ms

p50 (median):  13.5 ms
p95:           128.8 ms  <- 95% of queries are faster than this
p99:           426.0 ms  <- 99% of queries are faster than this

In AI, you'll use these to check:
  - Mean loss: is the model getting better? (should decrease)
  - Median accuracy: typical model performance
  - p99 latency: worst-case inference time
```

---

## Step 2. Standard deviation - how spread out is your data?

Standard deviation tells you how much your data varies. Low std = consistent. High std = all over the place.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# Two databases, same average query time, VERY different behavior
# Which would you rather manage?

# Database A: consistent (all queries about the same speed)
db_a = np.array([48, 50, 52, 49, 51, 50, 48, 52, 50, 50])

# Database B: unpredictable (some fast, some slow)
db_b = np.array([10, 90, 20, 80, 15, 85, 25, 75, 30, 70])

print("Database A (consistent):")
print(f"  Values: {db_a}")
print(f"  Mean:   {np.mean(db_a):.1f} ms")
# np.std() calculates standard deviation
# Small number = data points are close to the mean
print(f"  Std:    {np.std(db_a):.1f} ms  <- low = consistent")
print()

print("Database B (unpredictable):")
print(f"  Values: {db_b}")
print(f"  Mean:   {np.mean(db_b):.1f} ms")
# Large number = data points are spread far from the mean
print(f"  Std:    {np.std(db_b):.1f} ms  <- high = unpredictable")
print()

# Same average (50ms) but VERY different behavior!
print("Both have mean = 50ms, but:")
print("  DB A: you can predict query time (always ~50ms)")
print("  DB B: you can't predict anything (10ms to 90ms)")
print()

# --- What does the number actually mean? ---
# Standard deviation tells you: "most values are within this distance from the mean"
# Specifically:
#   68% of values are within 1 std dev of the mean
#   95% of values are within 2 std devs
#   99.7% of values are within 3 std devs

print("Standard deviation rule of thumb:")
mean_a = np.mean(db_a)
std_a = np.std(db_a)
print(f"  DB A: mean={mean_a:.1f}, std={std_a:.1f}")
print(f"  68% of queries: {mean_a - std_a:.1f} to {mean_a + std_a:.1f} ms")
print(f"  95% of queries: {mean_a - 2*std_a:.1f} to {mean_a + 2*std_a:.1f} ms")
print()

print("In AI:")
print("  - Low std in training loss = model is stable")
print("  - High std in training loss = model is bouncing around (reduce learning rate)")
print("  - High std in predictions = model is uncertain")
PYEOF
```

Expected output (yours will differ):
```
Database A (consistent):
  Values: [48 50 52 49 51 50 48 52 50 50]
  Mean:   50.0 ms
  Std:    1.3 ms  <- low = consistent

Database B (unpredictable):
  Values: [10 90 20 80 15 85 25 75 30 70]
  Mean:   50.0 ms
  Std:    30.0 ms  <- high = unpredictable

Both have mean = 50ms, but:
  DB A: you can predict query time (always ~50ms)
  DB B: you can't predict anything (10ms to 90ms)

Standard deviation rule of thumb:
  DB A: mean=50.0, std=1.3
  68% of queries: 48.7 to 51.3 ms
  95% of queries: 47.4 to 52.6 ms

In AI:
  - Low std in training loss = model is stable
  - High std in training loss = model is bouncing around (reduce learning rate)
  - High std in predictions = model is uncertain
```

---

## Step 3. Distributions - what does your data look like?

A distribution is the shape of your data when you plot it. Most data in nature follows a "normal distribution" (bell curve).

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# --- Normal distribution (bell curve) ---
# Most values cluster around the mean, fewer values far from the mean
# Like query response times on a healthy system

# np.random.seed(42) makes random numbers reproducible
# Without this, you'd get different numbers each run
np.random.seed(42)

# np.random.normal() generates random numbers from a normal distribution
# Parameters: mean, std_dev, count
#   mean = center of the bell curve
#   std_dev = how wide the bell curve is
#   count = how many numbers to generate
query_times = np.random.normal(loc=50, scale=10, size=1000)
# This generates 1000 query times centered around 50ms with std of 10ms

print("Normal distribution (1000 simulated query times):")
print(f"  Mean:   {np.mean(query_times):.1f} ms  (target: 50)")
print(f"  Std:    {np.std(query_times):.1f} ms  (target: 10)")
print(f"  Min:    {np.min(query_times):.1f} ms")
print(f"  Max:    {np.max(query_times):.1f} ms")
print()

# Count how many fall in each range
# This shows the bell curve shape
within_1std = np.sum(np.abs(query_times - 50) < 10)   # within 10ms of mean
within_2std = np.sum(np.abs(query_times - 50) < 20)   # within 20ms of mean
within_3std = np.sum(np.abs(query_times - 50) < 30)   # within 30ms of mean

# np.abs() = absolute value (makes negatives positive)
# np.sum() counts how many True values (True counts as 1)

print("Bell curve shape (should match 68/95/99.7 rule):")
print(f"  Within 1 std (40-60ms): {within_1std}/1000 = {within_1std/10:.1f}%  (expect ~68%)")
print(f"  Within 2 std (30-70ms): {within_2std}/1000 = {within_2std/10:.1f}%  (expect ~95%)")
print(f"  Within 3 std (20-80ms): {within_3std}/1000 = {within_3std/10:.1f}%  (expect ~99.7%)")
print()

# --- Text histogram (no matplotlib needed) ---
# Let's visualize the distribution with text
print("Distribution (text histogram):")
# np.histogram() counts values in each bucket (like GROUP BY ranges)
# bins=10 means "split into 10 buckets"
counts, edges = np.histogram(query_times, bins=10)
for i in range(len(counts)):
    # Create a text bar using # symbols
    bar = "#" * (counts[i] // 3)
    print(f"  {edges[i]:5.0f}-{edges[i+1]:5.0f}ms: {bar} ({counts[i]})")

print()
print("In AI:")
print("  - Model weights start from a normal distribution")
print("  - Data normalization: rescale data to mean=0, std=1")
print("  - Batch normalization: keep layer outputs normally distributed")
PYEOF
```

Expected output (yours will differ):
```
Normal distribution (1000 simulated query times):
  Mean:   49.8 ms  (target: 50)
  Std:    9.8 ms  (target: 10)
  Min:    18.3 ms
  Max:    82.0 ms

Bell curve shape (should match 68/95/99.7 rule):
  Within 1 std (40-60ms): 682/1000 = 68.2%  (expect ~68%)
  Within 2 std (30-70ms): 958/1000 = 95.8%  (expect ~95%)
  Within 3 std (20-80ms): 997/1000 = 99.7%  (expect ~99.7%)

Distribution (text histogram):
     18-  24ms:  (3)
     24-  31ms: ## (8)
     31-  37ms: ############ (38)
     37-  44ms: ############################## (92)
     44-  50ms: ############################################### (143)
     50-  57ms: ################################################ (146)
     57-  63ms: ############################################# (136)
     63-  70ms: ##################### (65)
     70-  76ms: ##### (16)
     76-  82ms: # (5)

In AI:
  - Model weights start from a normal distribution
  - Data normalization: rescale data to mean=0, std=1
  - Batch normalization: keep layer outputs normally distributed
```

---

## Step 4. Normalization - putting data on the same scale

If one feature is in milliseconds (0-500) and another is a percentage (0-100), the big numbers will dominate. Normalization puts everything on the same scale.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

# Server metrics - different scales!
# CPU is 0-100, Memory is 0-100, Connections is 0-300, Disk is 0-2000GB
raw_data = np.array([
    [92.5,  68.3, 285,  450],   # server A
    [15.2,  42.1,  25, 1200],   # server B
    [55.0,  51.0, 150,  800],   # server C
])

print("Raw data (different scales):")
print(f"  Server A: CPU={raw_data[0,0]}%, Mem={raw_data[0,1]}%, Conn={raw_data[0,2]}, Disk={raw_data[0,3]}GB")
print(f"  Server B: CPU={raw_data[1,0]}%, Mem={raw_data[1,1]}%, Conn={raw_data[1,2]}, Disk={raw_data[1,3]}GB")
print()
print("Problem: Disk (0-2000) will dominate over CPU (0-100)")
print("  Distance between servers will be mostly about disk size")
print()

# --- Method 1: Min-Max normalization (scale to 0-1) ---
# Formula: (value - min) / (max - min)
# Every value becomes a number between 0 and 1
#
# axis=0 means "calculate min/max for each COLUMN"
# keepdims=True keeps the shape so subtraction works
col_min = raw_data.min(axis=0)
col_max = raw_data.max(axis=0)
minmax = (raw_data - col_min) / (col_max - col_min)

print("Method 1: Min-Max normalization (0 to 1):")
print(f"  Server A: {minmax[0]}")
print(f"  Server B: {minmax[1]}")
print(f"  Server C: {minmax[2]}")
print("  Now all features are 0-1, no feature dominates")
print()

# --- Method 2: Z-score normalization (mean=0, std=1) ---
# Formula: (value - mean) / std
# Positive = above average, Negative = below average
#
# This is the most common in AI - called "standardization"
col_mean = raw_data.mean(axis=0)
col_std = raw_data.std(axis=0)
zscore = (raw_data - col_mean) / col_std

print("Method 2: Z-score normalization (mean=0, std=1):")
print(f"  Server A: [{', '.join(f'{v:.2f}' for v in zscore[0])}]")
print(f"  Server B: [{', '.join(f'{v:.2f}' for v in zscore[1])}]")
print(f"  Server C: [{', '.join(f'{v:.2f}' for v in zscore[2])}]")
print()
print("  Positive = above average for that metric")
print("  Negative = below average for that metric")
print("  Server A: high CPU (+1.1), high connections (+1.1)")
print("  Server B: low CPU (-1.0), high disk (+1.1)")
print()

# Verify: after z-score, mean should be ~0 and std should be ~1
print("Verify z-score normalization:")
print(f"  Column means: {zscore.mean(axis=0).round(1)}")
print(f"  Column stds:  {zscore.std(axis=0).round(1)}")
print()

print("Why normalize before AI?")
print("  Without: model focuses on large-scale features (disk) and ignores small ones (CPU)")
print("  With: model treats all features equally, learns real patterns")
print("  Rule: ALWAYS normalize your data before feeding it to a model")
PYEOF
```

Expected output (yours will differ):
```
Raw data (different scales):
  Server A: CPU=92.5%, Mem=68.3%, Conn=285, Disk=450GB
  Server B: CPU=15.2%, Mem=42.1%, Conn=25, Disk=1200GB

Problem: Disk (0-2000) will dominate over CPU (0-100)
  Distance between servers will be mostly about disk size

Method 1: Min-Max normalization (0 to 1):
  Server A: [1.   1.   1.   0.  ]
  Server B: [0.   0.   0.   1.  ]
  Server C: [0.515 0.340 0.481 0.467]
  Now all features are 0-1, no feature dominates

Method 2: Z-score normalization (mean=0, std=1):
  Server A: [1.09, 1.13, 1.09, -1.09]
  Server B: [-1.04, -1.03, -1.04, 1.09]
  Server C: [-0.05, -0.10, -0.05, 0.00]

  Positive = above average for that metric
  Negative = below average for that metric
  Server A: high CPU (+1.1), high connections (+1.1)
  Server B: low CPU (-1.0), high disk (+1.1)

Verify z-score normalization:
  Column means: [ 0. -0.  0. -0.]
  Column stds:  [1. 1. 1. 1.]

Why normalize before AI?
  Without: model focuses on large-scale features (disk) and ignores small ones (CPU)
  With: model treats all features equally, learns real patterns
  Rule: ALWAYS normalize your data before feeding it to a model
```

---

## Step 5. Correlation - do two things move together?

Correlation tells you if two metrics are related. If CPU goes up when connections go up, they're correlated.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np

np.random.seed(42)

# Simulated server data over 50 time points
n = 50

# Connections increase over time (simulated load test)
connections = np.linspace(10, 300, n)  # 10 to 300, evenly spaced
# np.linspace(start, stop, count) creates evenly spaced numbers

# CPU goes up WITH connections (strong positive correlation)
# np.random.normal(0, 5, n) adds small random noise
cpu = connections * 0.3 + np.random.normal(0, 5, n)

# Memory stays mostly flat (weak correlation with connections)
memory = 50 + np.random.normal(0, 8, n)

# Disk free space goes DOWN as connections go up (negative correlation)
disk_free = 500 - connections * 0.5 + np.random.normal(0, 10, n)

# --- Calculate correlations ---
# np.corrcoef() returns a correlation matrix
# Values range from -1 to +1:
#   +1 = perfect positive (one goes up, other goes up)
#    0 = no relationship
#   -1 = perfect negative (one goes up, other goes down)

# Stack our data into columns
# np.column_stack() puts arrays side by side as columns
data = np.column_stack([connections, cpu, memory, disk_free])
labels = ["Connections", "CPU", "Memory", "Disk Free"]

# Calculate the correlation matrix
# This is like running correlation between every pair of columns
corr = np.corrcoef(data, rowvar=False)
# rowvar=False means "columns are variables, rows are observations"

print("Correlation matrix:")
print(f"{'':>14s}", end="")
for l in labels:
    print(f"{l:>14s}", end="")
print()

for i, label in enumerate(labels):
    print(f"{label:>14s}", end="")
    for j in range(len(labels)):
        val = corr[i, j]
        print(f"{val:>14.3f}", end="")
    print()

print()
print("Reading the matrix:")
print(f"  Connections vs CPU:       {corr[0,1]:+.3f}  (strong positive - CPU rises with connections)")
print(f"  Connections vs Memory:    {corr[0,2]:+.3f}  (weak - memory doesn't depend on connections)")
print(f"  Connections vs Disk Free: {corr[0,3]:+.3f}  (strong negative - disk fills as connections grow)")
print()
print("In AI:")
print("  - Highly correlated features are redundant (pick one, drop the other)")
print("  - Zero correlation means the feature provides unique information")
print("  - Feature selection: keep features with low correlation to each other")
print("    but high correlation to the target (what you're predicting)")
PYEOF
```

Expected output (yours will differ):
```
Correlation matrix:
                 Connections           CPU        Memory     Disk Free
   Connections         1.000         0.993         0.017        -0.996
           CPU         0.993         1.000         0.024        -0.990
        Memory         0.017         0.024         1.000        -0.019
     Disk Free        -0.996        -0.990        -0.019         1.000

Reading the matrix:
  Connections vs CPU:       +0.993  (strong positive - CPU rises with connections)
  Connections vs Memory:    +0.017  (weak - memory doesn't depend on connections)
  Connections vs Disk Free: -0.996  (strong negative - disk fills as connections grow)

In AI:
  - Highly correlated features are redundant (pick one, drop the other)
  - Zero correlation means the feature provides unique information
  - Feature selection: keep features with low correlation to each other
    but high correlation to the target (what you're predicting)
```

---

## What You Learned

| Concept | What It Is | DBA Analogy | AI Use |
|---------|-----------|-------------|--------|
| Mean | Average value | `avg()` | Average model error (loss) |
| Median | Middle value (ignores outliers) | `percentile_cont(0.5)` | Robust performance measure |
| Std dev | How spread out data is | `stddev()` | Model stability, uncertainty |
| Percentiles | Value below X% of data | `percentile_cont(0.95)` | p95/p99 latency monitoring |
| Normal distribution | Bell curve shape | Healthy query time pattern | Weight initialization, normalization |
| Min-Max normalization | Scale to 0-1 | N/A | Prepare data for models |
| Z-score normalization | Scale to mean=0, std=1 | N/A | Most common AI preprocessing |
| Correlation | Do two things move together? | Correlated metrics | Feature selection |
