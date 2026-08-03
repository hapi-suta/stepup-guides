# Build 03: Matplotlib Visualization

Matplotlib makes charts from your data. Think of it as building Grafana dashboards in code. You'll use it to visualize training loss, compare model performance, and spot data patterns.

---

## Step 1. Bar chart - compare categories

A bar chart answers: "Which category has the highest/lowest value?" Same as a Grafana bar panel.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

databases = ['PostgreSQL', 'MySQL', 'MongoDB', 'Redis']
avg_times = [224.6, 150.0, 89.0, 2.5]

plt.figure(figsize=(8, 5))
plt.bar(databases, avg_times, color=['#336791', '#4479A1', '#47A248', '#DC382D'])
plt.title('Average Query Duration by Database')
plt.xlabel('Database')
plt.ylabel('Duration (ms)')
plt.tight_layout()
plt.savefig('/tmp/chart_bar.png', dpi=100)
print('Saved: /tmp/chart_bar.png')
PYEOF
```

Expected output:
```
Saved: /tmp/chart_bar.png
```

Open the chart to see it:

```bash
open /tmp/chart_bar.png
```

- `matplotlib.use('Agg')` tells Matplotlib to save to file instead of opening a window
- `plt.figure(figsize=(8, 5))` sets the chart size in inches (width, height)
- `plt.bar()` creates a bar chart. First argument is labels, second is values.
- `plt.savefig()` saves the chart as an image. `dpi=100` controls resolution.
- Colors use hex codes - same as CSS/HTML

---

## Step 2. Line chart - track changes over time

A line chart answers: "How does this value change over time?" Like a Grafana time-series panel.

```bash
python3 << 'PYEOF'
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

np.random.seed(42)
minutes = np.arange(0, 60)
# .cumsum() = cumulative sum. Each value is the running total of all previous values.
# Combined with random numbers, it creates a realistic "wandering" line.
cpu_primary = 40 + np.random.randn(60).cumsum() * 2
cpu_standby = 25 + np.random.randn(60).cumsum() * 1.5

plt.figure(figsize=(10, 5))
plt.plot(minutes, cpu_primary, label='pg-primary', color='#e74c3c', linewidth=2)
plt.plot(minutes, cpu_standby, label='pg-standby', color='#3498db', linewidth=2)
plt.title('CPU Usage Over Time')
plt.xlabel('Minutes')
plt.ylabel('CPU %')
plt.legend()
plt.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('/tmp/chart_line.png', dpi=100)
print('Saved: /tmp/chart_line.png')
PYEOF
```

Expected output:
```
Saved: /tmp/chart_line.png
```

```bash
open /tmp/chart_line.png
```

- `plt.plot()` draws a line. Call it multiple times for multiple lines.
- `label=` names each line for the legend
- `plt.legend()` shows the legend box
- `plt.grid(True, alpha=0.3)` adds a light grid (alpha controls transparency)
- `np.random.randn(60).cumsum()` generates random walk data (simulates real metrics)

---

## Step 3. Scatter plot - find relationships

A scatter plot answers: "Is there a relationship between X and Y?" This is how you spot patterns in data before building a model.

```bash
python3 << 'PYEOF'
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

np.random.seed(42)
rows = np.random.randint(10, 50000, 50)
times = rows * 0.015 + np.random.randn(50) * 20 + 10
# np.clip() limits values to a range - here, no query time below 1ms
times = np.clip(times, 1, None)

plt.figure(figsize=(8, 5))
plt.scatter(rows, times, alpha=0.6, color='#336791', edgecolors='white', linewidth=0.5)
plt.title('Query Time vs Rows Returned')
plt.xlabel('Rows Returned')
plt.ylabel('Query Time (ms)')
plt.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('/tmp/chart_scatter.png', dpi=100)
print('Saved: /tmp/chart_scatter.png')
PYEOF
```

Expected output:
```
Saved: /tmp/chart_scatter.png
```

```bash
open /tmp/chart_scatter.png
```

- `plt.scatter()` draws a dot for each data point
- `alpha=0.6` makes dots semi-transparent so overlapping points are visible
- The upward trend shows: more rows returned = longer query time. That's a **correlation** - a relationship a model could learn.

---

## Step 4. Histogram - see data distribution

A histogram answers: "What does the spread of my data look like?" Critical for understanding if your training data is balanced or skewed.

```bash
python3 << 'PYEOF'
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

np.random.seed(42)
# np.concatenate() joins multiple arrays into one - like UNION ALL in SQL.
# np.random.normal(50, 15, 800) generates 800 random numbers centered at 50,
#   with a spread of 15. The three arguments: (center, spread, count).
query_times = np.concatenate([
    np.random.normal(50, 15, 800),
    np.random.normal(300, 50, 200)
])
# np.clip(values, min, max) limits values to a range.
# clip(query_times, 1, None) means "nothing below 1, no upper limit."
query_times = np.clip(query_times, 1, None)

plt.figure(figsize=(8, 5))
plt.hist(query_times, bins=40, color='#336791', edgecolor='white', alpha=0.8)
plt.title('Distribution of Query Times')
plt.xlabel('Query Time (ms)')
plt.ylabel('Number of Queries')
plt.axvline(x=np.median(query_times), color='red', linestyle='--', label=f'Median: {np.median(query_times):.0f}ms')
plt.axvline(x=np.mean(query_times), color='orange', linestyle='--', label=f'Mean: {np.mean(query_times):.0f}ms')
plt.legend()
plt.tight_layout()
plt.savefig('/tmp/chart_hist.png', dpi=100)
print('Saved: /tmp/chart_hist.png')
print(f'Mean: {np.mean(query_times):.1f}ms')
print(f'Median: {np.median(query_times):.1f}ms')
print(f'Total queries: {len(query_times)}')
PYEOF
```

Expected output (yours will differ):
```
Saved: /tmp/chart_hist.png
Mean: 99.4ms
Median: 57.7ms
Total queries: 1000
```

```bash
open /tmp/chart_hist.png
```

- `plt.hist()` groups data into bins and counts how many fall in each bin
- `bins=40` controls how many bars to show (more bins = more detail)
- `plt.axvline()` draws a vertical line - useful for marking thresholds
- The mean (99ms) is much higher than the median (58ms) - that tells you the data is **skewed right** (a few very slow queries pull the average up). This is common in query logs.
- In AI, skewed data means your model might be biased toward the common case and miss the rare cases. You'd need to rebalance.

---

## Step 5. Subplots - multiple charts in one figure

When you need to see several things at once - like a Grafana dashboard with multiple panels.

```bash
python3 << 'PYEOF'
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

np.random.seed(42)

# Tuple unpacking: plt.subplots returns two things (figure, axes).
# "fig, axes = ..." assigns each to its own variable.
# DBA analogy: SELECT fig, axes INTO v_fig, v_axes
fig, axes = plt.subplots(2, 2, figsize=(12, 8))

# Top left: bar chart
databases = ['PG', 'MySQL', 'Mongo', 'Redis']
counts = [5, 2, 1, 2]
axes[0, 0].bar(databases, counts, color='#336791')
axes[0, 0].set_title('Queries by Database')
axes[0, 0].set_ylabel('Count')

# Top right: line chart
x = np.arange(10)
axes[0, 1].plot(x, np.random.randn(10).cumsum(), 'r-', label='Errors')
axes[0, 1].plot(x, np.random.randn(10).cumsum(), 'b-', label='Warnings')
axes[0, 1].set_title('Errors Over Time')
axes[0, 1].legend()

# Bottom left: scatter
axes[1, 0].scatter(np.random.rand(30), np.random.rand(30), alpha=0.6)
axes[1, 0].set_title('CPU vs Memory')

# Bottom right: histogram
axes[1, 1].hist(np.random.normal(100, 30, 500), bins=25, color='#47A248')
axes[1, 1].set_title('Response Time Distribution')

plt.suptitle('Database Monitoring Dashboard', fontsize=14, fontweight='bold')
plt.tight_layout()
plt.savefig('/tmp/chart_dashboard.png', dpi=100)
print('Saved: /tmp/chart_dashboard.png')
PYEOF
```

Expected output:
```
Saved: /tmp/chart_dashboard.png
```

```bash
open /tmp/chart_dashboard.png
```

- `plt.subplots(2, 2)` creates a 2x2 grid of charts
- `axes[row, col]` accesses each individual chart
- `plt.suptitle()` adds a title above all charts
- This is the pattern you'll use to visualize model training: loss curve, accuracy, confusion matrix, and predictions all in one view

---

## What You Learned

| Chart Type | Question It Answers | AI Use Case |
|-----------|-------------------|-------------|
| Bar chart | Which category is highest/lowest? | Compare model accuracy across classes |
| Line chart | How does it change over time? | Training loss curves |
| Scatter plot | Is there a relationship? | Feature correlation, embedding clusters |
| Histogram | What's the distribution? | Check if training data is balanced |
| Subplots | Multiple views at once | Training dashboard (loss, accuracy, samples) |
