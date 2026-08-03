# USE 01: Math for AI Exercises

Practice what you built. Each exercise reinforces a concept from Builds 01-04.

---

## Exercise 1: Server Similarity Detector (Vectors)

Build a tool that takes server metrics and finds the most similar server in your fleet.

**Setup data:**
```python
import numpy as np

# Fleet of 5 servers: [CPU%, Memory%, Disk%, Connections (normalized 0-1)]
fleet = {
    "pg-primary":  np.array([0.45, 0.62, 0.30, 0.50]),
    "pg-standby":  np.array([0.25, 0.40, 0.30, 0.17]),
    "pg-analytics": np.array([0.92, 0.85, 0.70, 0.90]),
    "pg-dev":      np.array([0.10, 0.20, 0.15, 0.05]),
    "pg-staging":  np.array([0.48, 0.60, 0.32, 0.52]),
}

# A new alert comes in for this server:
alert_server = np.array([0.90, 0.82, 0.68, 0.88])
```

**Task:**
1. Calculate the cosine similarity between `alert_server` and every server in the fleet
2. Print all similarities, sorted highest to lowest
3. Identify which server the alert is most similar to
4. Print: "Alert server behaves most like: [server name]"

**Expected result:** The alert server should be most similar to `pg-analytics` (both are high-resource servers).

**Hint:** Use the `cosine_sim()` function from Build 01 Step 5.

---

## Exercise 2: Anomaly Detection with Z-Scores (Statistics)

Use z-score normalization to detect anomalous servers.

**Setup data:**
```python
import numpy as np

# 10 days of CPU readings for one server
cpu_history = np.array([45, 48, 42, 50, 47, 44, 46, 49, 43, 47])

# Today's reading
today_cpu = 92
```

**Task:**
1. Calculate the mean and standard deviation of `cpu_history`
2. Calculate the z-score for `today_cpu`: `z = (today - mean) / std`
3. Print the z-score
4. If z-score > 2: print "ANOMALY: CPU is more than 2 standard deviations above normal"
5. If z-score > 3: print "CRITICAL: CPU is more than 3 standard deviations above normal"
6. Print what "normal range" looks like (mean +/- 2 std devs)

**Expected result:** Today's CPU (92%) should be flagged as an anomaly since the normal range is roughly 40-52%.

---

## Exercise 3: Feature Importance from Weights (Matrices)

Train a simple linear model and interpret which features matter most.

**Setup data:**
```python
import numpy as np
np.random.seed(42)

# 20 servers: [CPU, Memory, Disk, WAL_growth, Connection_count]
# All normalized to 0-1
X = np.random.rand(20, 5)

# Label: 1 = incident within 24 hours, 0 = no incident
# Rule: incidents happen when CPU > 0.7 AND connections > 0.7
y = ((X[:, 0] > 0.7) & (X[:, 4] > 0.7)).astype(float)
```

**Task:**
1. Train a single-layer model (like Build 04 Step 5) for 200 steps
2. After training, print the 5 weights
3. Rank features by absolute weight value (highest = most important)
4. Answer: which two features does the model think are most predictive?

**Expected result:** CPU (column 0) and Connection_count (column 4) should have the highest weights, since those are the features that actually determine incidents.

**Hint:** Use the sigmoid + gradient descent pattern from Build 04 Step 5.

---

## Exercise 4: Normalize and Compare (Statistics + Vectors)

Raw metrics are on different scales. Normalize them, then find similar servers.

**Setup data:**
```python
import numpy as np

# Raw server data: [CPU%, Memory_MB, Connections, Disk_GB, WAL_MB]
# Notice: Memory is in MB (0-16384), Disk in GB (0-2000), etc.
servers = np.array([
    [85, 12000, 280, 450, 800],     # server A
    [20,  4000,  30, 1800, 100],    # server B
    [82, 11500, 270, 500, 750],     # server C
    [25,  5000,  40, 1700, 150],    # server D
])
```

**Task:**
1. Without normalization: calculate Euclidean distance between all pairs of servers
2. With z-score normalization: calculate distance between all pairs
3. Compare results: which pairs change the most?
4. Explain: why does normalization change the similarity rankings?

**Expected result:** Without normalization, distance is dominated by Memory and Disk (big numbers). With normalization, you see that A&C are similar (both high CPU/connections) and B&D are similar (both low CPU/connections).

---

## Exercise 5: Learning Rate Explorer (Calculus)

Visualize how different learning rates affect training.

**Task:**
1. Use the training setup from Build 04 (inputs = [1,2,3,4,5], targets = [2,4,6,8,10])
2. Train with 5 different learning rates: 0.001, 0.01, 0.04, 0.1, 0.2
3. For each, record the loss at every step for 50 steps
4. Print a summary table:

```
Learning Rate | Loss at step 5 | Loss at step 20 | Loss at step 50 | Converged?
------------- | --------------- | ---------------- | ---------------- | ----------
0.001         | ...             | ...              | ...              | No
0.01          | ...             | ...              | ...              | Almost
0.04          | ...             | ...              | ...              | Yes
0.1           | ...             | ...              | ...              | Yes
0.2           | ...             | ...              | ...              | Exploded!
```

5. Answer: what's the highest learning rate that still converges for this problem?

**Hint:** "Converged" means loss < 0.01 by step 50. "Exploded" means loss increased instead of decreased.

---

## Scoring Guide

| Exercise | Skill Tested | Difficulty |
|----------|-------------|------------|
| 1 | Cosine similarity, vector operations | Beginner |
| 2 | Z-score, anomaly detection | Beginner |
| 3 | Matrix multiply, gradient descent, interpretation | Intermediate |
| 4 | Normalization, distance, before/after comparison | Intermediate |
| 5 | Learning rate tuning, training dynamics | Intermediate |
