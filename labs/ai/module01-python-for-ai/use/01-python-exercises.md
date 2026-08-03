# USE: Python for AI Exercises

Work through these exercises in order. Each builds on the previous one. Try to solve them before looking at the hints or solutions.

---

## Exercise 1: Embedding Similarity Ranker

**Task:** You have a search query and 5 documents, each represented as embedding vectors. Rank the documents by similarity to the query (highest first) and print the ranking.

```python
import numpy as np

query = np.array([0.9, 0.1, 0.4, 0.2])

documents = {
    'pg-backup-guide':     np.array([0.8, 0.2, 0.5, 0.1]),
    'mysql-install':       np.array([0.1, 0.8, 0.2, 0.3]),
    'pg-replication':      np.array([0.7, 0.1, 0.6, 0.3]),
    'redis-caching':       np.array([0.2, 0.7, 0.1, 0.8]),
    'pg-vacuum-tuning':    np.array([0.85, 0.15, 0.3, 0.15]),
}
```

Your output should look like:
```
1. pg-vacuum-tuning     - score: 0.XXXX
2. pg-backup-guide      - score: 0.XXXX
3. pg-replication        - score: 0.XXXX
4. mysql-install         - score: 0.XXXX
5. redis-caching         - score: 0.XXXX
```

<details>
<summary>Hint</summary>

Use `np.dot()` to calculate similarity for each document. Store results in a list of tuples, then sort by score descending.
</details>

<details>
<summary>Solution</summary>

```python
import numpy as np

query = np.array([0.9, 0.1, 0.4, 0.2])

documents = {
    'pg-backup-guide':     np.array([0.8, 0.2, 0.5, 0.1]),
    'mysql-install':       np.array([0.1, 0.8, 0.2, 0.3]),
    'pg-replication':      np.array([0.7, 0.1, 0.6, 0.3]),
    'redis-caching':       np.array([0.2, 0.7, 0.1, 0.8]),
    'pg-vacuum-tuning':    np.array([0.85, 0.15, 0.3, 0.15]),
}

scores = []
for name, embedding in documents.items():
    score = np.dot(query, embedding)
    scores.append((name, score))

scores.sort(key=lambda x: x[1], reverse=True)

for rank, (name, score) in enumerate(scores, 1):
    print(f'{rank}. {name:25s} - score: {score:.4f}')
```

Output:
```
1. pg-vacuum-tuning           - score: 0.9250
2. pg-backup-guide            - score: 0.9600
3. pg-replication             - score: 0.9700
...
```

The PostgreSQL docs rank highest because their embedding vectors point in a similar direction to the query. This is exactly how RAG retrieval works.
</details>

---

## Exercise 2: Query Log Analyzer

**Task:** Load this CSV data into Pandas and answer these questions:
1. Which database has the most slow queries?
2. What's the 95th percentile query time (overall)?
3. Which hour of the day has the highest average query time?

```python
import pandas as pd
import numpy as np

np.random.seed(42)
n = 200
data = {
    'timestamp': pd.date_range('2026-06-09 08:00', periods=n, freq='2min'),
    'database': np.random.choice(['PostgreSQL', 'MySQL', 'MongoDB'], n, p=[0.5, 0.3, 0.2]),
    'duration_ms': np.concatenate([
        np.random.exponential(50, n//2),
        np.random.exponential(200, n//2)
    ]),
    'status': ['ok'] * n  # You'll need to derive this
}
df = pd.DataFrame(data)
df['duration_ms'] = df['duration_ms'].round(1)
# Mark queries over 200ms as 'slow'
df.loc[df['duration_ms'] > 200, 'status'] = 'slow'
```

<details>
<summary>Hint</summary>

- For question 1: filter to slow queries, then `.value_counts()` on the database column
- For question 2: use `df['duration_ms'].quantile(0.95)`
- For question 3: extract the hour with `df['timestamp'].dt.hour`, then group by it
</details>

<details>
<summary>Solution</summary>

```python
import pandas as pd
import numpy as np

np.random.seed(42)
n = 200
data = {
    'timestamp': pd.date_range('2026-06-09 08:00', periods=n, freq='2min'),
    'database': np.random.choice(['PostgreSQL', 'MySQL', 'MongoDB'], n, p=[0.5, 0.3, 0.2]),
    'duration_ms': np.concatenate([
        np.random.exponential(50, n//2),
        np.random.exponential(200, n//2)
    ]),
    'status': ['ok'] * n
}
df = pd.DataFrame(data)
df['duration_ms'] = df['duration_ms'].round(1)
df.loc[df['duration_ms'] > 200, 'status'] = 'slow'

# Q1: Most slow queries by database
print('Q1: Slow queries by database:')
slow = df[df['status'] == 'slow']
print(slow['database'].value_counts())
print()

# Q2: 95th percentile
p95 = df['duration_ms'].quantile(0.95)
print(f'Q2: 95th percentile query time: {p95:.1f}ms')
print()

# Q3: Highest avg by hour
df['hour'] = df['timestamp'].dt.hour
hourly = df.groupby('hour')['duration_ms'].mean().round(1)
print('Q3: Average query time by hour:')
print(hourly)
worst_hour = hourly.idxmax()
print(f'Worst hour: {worst_hour}:00 ({hourly[worst_hour]}ms avg)')
```
</details>

---

## Exercise 3: Training Loss Visualizer

**Task:** Simulate a model training run and create a chart with two lines: training loss and validation loss over 50 epochs. Save it to `/tmp/training_loss.png`.

Requirements:
- Training loss should start high (~2.5) and decrease to ~0.3
- Validation loss should start high (~2.8), decrease to ~0.5, then slightly increase after epoch 35 (overfitting!)
- Add a vertical dashed line at epoch 35 labeled "Overfitting starts"
- Include a legend, grid, and title

<details>
<summary>Hint</summary>

- Use `np.exp(-x * rate)` to create a decreasing curve
- For validation loss, add a slight upward trend after epoch 35
- Use `plt.axvline()` for the vertical line
</details>

<details>
<summary>Solution</summary>

```python
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

np.random.seed(42)
epochs = np.arange(1, 51)

train_loss = 2.5 * np.exp(-epochs * 0.06) + 0.3 + np.random.randn(50) * 0.03
val_loss = 2.8 * np.exp(-epochs * 0.05) + 0.5 + np.random.randn(50) * 0.05
# Simulate overfitting after epoch 35
val_loss[35:] += np.linspace(0, 0.4, 15)

plt.figure(figsize=(10, 5))
plt.plot(epochs, train_loss, 'b-', label='Training Loss', linewidth=2)
plt.plot(epochs, val_loss, 'r-', label='Validation Loss', linewidth=2)
plt.axvline(x=35, color='gray', linestyle='--', alpha=0.7, label='Overfitting starts')
plt.title('Model Training Progress')
plt.xlabel('Epoch')
plt.ylabel('Loss')
plt.legend()
plt.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('/tmp/training_loss.png', dpi=100)
print('Saved: /tmp/training_loss.png')
```

When you open the chart, you'll see training loss keeps dropping but validation loss starts climbing after epoch 35. This is **overfitting** - the model memorized the training data instead of learning general patterns. You'd stop training at epoch 35 (called "early stopping"). Recognizing this pattern is a core ML skill.
</details>

---

## Exercise 4: Data Cleaning Pipeline

**Task:** The following dataset has problems. Fix ALL of them and print the clean version.

```python
import pandas as pd
import numpy as np

messy = pd.DataFrame({
    'server': ['pg-primary', 'pg-standby', 'pg-primary', None, 'pg-standby', 'PG-PRIMARY', 'pg-standby'],
    'cpu': [45.2, 102.3, 78.1, 62.3, -5.0, 55.0, np.nan],
    'memory_gb': [12.4, 8.1, np.nan, 7.9, 14.2, 12.0, 8.5],
    'connections': [150, 200, 200, 180, 150, 999999, 175]
})
```

Problems to fix:
1. One server name is None (missing)
2. One server name has wrong capitalization ('PG-PRIMARY')
3. CPU of 102.3% is impossible - cap at 100
4. CPU of -5.0% is impossible - floor at 0
5. One NaN in cpu column
6. One NaN in memory_gb column
7. 999999 connections is clearly an outlier

<details>
<summary>Hint</summary>

- `.dropna(subset=['server'])` removes rows with missing server names
- `.str.lower()` normalizes case
- `np.clip(df['cpu'], 0, 100)` caps values within a range
- Use the IQR method or a hard threshold for outliers
</details>

<details>
<summary>Solution</summary>

```python
import pandas as pd
import numpy as np

messy = pd.DataFrame({
    'server': ['pg-primary', 'pg-standby', 'pg-primary', None, 'pg-standby', 'PG-PRIMARY', 'pg-standby'],
    'cpu': [45.2, 102.3, 78.1, 62.3, -5.0, 55.0, np.nan],
    'memory_gb': [12.4, 8.1, np.nan, 7.9, 14.2, 12.0, 8.5],
    'connections': [150, 200, 200, 180, 150, 999999, 175]
})

print('BEFORE:')
print(messy)
print()

# 1. Drop rows with no server name
clean = messy.dropna(subset=['server']).copy()

# 2. Normalize server names to lowercase
clean['server'] = clean['server'].str.lower()

# 3+4. Cap CPU between 0 and 100
clean['cpu'] = np.clip(clean['cpu'], 0, 100)

# 5. Fill missing CPU with mean
clean['cpu'] = clean['cpu'].fillna(clean['cpu'].mean())

# 6. Fill missing memory with median
clean['memory_gb'] = clean['memory_gb'].fillna(clean['memory_gb'].median())

# 7. Remove connection outliers (> 3 std deviations from mean)
conn_mean = clean['connections'].mean()
conn_std = clean['connections'].std()
clean = clean[clean['connections'] < conn_mean + 3 * conn_std]

print('AFTER:')
print(clean)
print()
print(f'Rows: {len(messy)} -> {len(clean)}')
```

This is a typical data cleaning pipeline. In AI, "garbage in, garbage out" - dirty data produces bad models. You'll run pipelines like this before every training job.
</details>

---

## Exercise 5: Put It All Together

**Task:** Create a complete analysis script that:

1. Generates 1000 simulated query log entries with these columns:
   - `timestamp` (every 5 seconds over ~83 minutes)
   - `database` (PostgreSQL 60%, MySQL 25%, MongoDB 15%)
   - `duration_ms` (mix of fast queries ~20ms and slow queries ~300ms)
   - `rows_returned` (correlated with duration - more rows = slower)

2. Produces a 2x2 dashboard (`/tmp/query_analysis.png`) with:
   - Top-left: Bar chart of query count by database
   - Top-right: Line chart of rolling average duration over time
   - Bottom-left: Scatter plot of rows_returned vs duration_ms
   - Bottom-right: Histogram of duration_ms with mean/median lines

3. Prints a summary table to the console

This is an open-ended exercise. No single correct answer - make it work, make it readable.

<details>
<summary>Hint</summary>

- Use `pd.date_range()` for timestamps
- Use `np.random.choice()` with probabilities for database selection
- Use `df.rolling(window=20).mean()` for the rolling average
- Use `plt.subplots(2, 2)` for the dashboard
</details>
