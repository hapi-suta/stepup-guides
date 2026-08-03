# Build 04: K-Means Clustering - Grouping Similar Things

All the models so far had labels - you told the model "this is healthy, this is an incident." Clustering finds groups in your data WITHOUT labels. It discovers patterns you didn't know existed.

---

## Step 1. What is clustering?

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd

print("""
Supervised Learning (Builds 01-03):
  You have labels. You tell the model the answer.
  "This server is healthy, this one had an incident."
  Model learns to predict labels for new data.

Unsupervised Learning (this build):
  No labels. The model finds patterns on its own.
  "Here are 500 servers. Group similar ones together."
  You don't tell it what the groups should be.

DBA analogy:
  Supervised = "Here's a runbook. Learn to follow it."
  Unsupervised = "Here's raw data. Find the patterns yourself."

When to use clustering:
  - Group servers by workload pattern (OLTP, OLAP, idle)
  - Find anomalous queries (which don't fit any group)
  - Customer segmentation (which users behave similarly)
  - Log analysis (group similar error patterns)
""")
PYEOF
```

---

## Step 2. K-Means clustering

K-Means groups data into K clusters by finding K center points and assigning each data point to the nearest center.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

# --- Create server data (no labels!) ---
np.random.seed(42)

# Simulate 3 types of servers (but we'll pretend we don't know this)
# Type 1: OLTP (high connections, moderate CPU, low disk)
oltp = np.column_stack([
    np.random.normal(60, 10, 50),    # CPU
    np.random.normal(200, 30, 50),   # Connections
    np.random.normal(30, 5, 50),     # Disk %
])

# Type 2: OLAP (high CPU, low connections, high disk)
olap = np.column_stack([
    np.random.normal(85, 8, 50),     # CPU
    np.random.normal(20, 10, 50),    # Connections
    np.random.normal(75, 10, 50),    # Disk %
])

# Type 3: Idle (low everything)
idle = np.column_stack([
    np.random.normal(15, 5, 50),     # CPU
    np.random.normal(5, 3, 50),      # Connections
    np.random.normal(20, 5, 50),     # Disk %
])

# Combine all servers into one dataset
# np.vstack() stacks arrays on top of each other (vertically)
data = np.vstack([oltp, olap, idle])
df = pd.DataFrame(data, columns=['cpu_percent', 'connections', 'disk_percent'])

print(f"150 servers, 3 features each")
print(f"We DON'T know there are 3 types. The algorithm will discover them.")
print()

# --- Normalize the data ---
# K-Means uses distance, so features must be on the same scale
# StandardScaler does z-score normalization: (value - mean) / std
scaler = StandardScaler()
X_scaled = scaler.fit_transform(df)

# fit_transform() does two things:
#   fit: calculates mean and std from the data
#   transform: applies (value - mean) / std to every value

print(f"Before scaling - mean: {df.mean().values.round(1)}")
print(f"After scaling  - mean: {X_scaled.mean(axis=0).round(4)}")
print()

# --- Run K-Means ---
# n_clusters=3 means "find 3 groups"
# In real life, you'd try different values of K (Step 3)
kmeans = KMeans(n_clusters=3, random_state=42, n_init=10)
# n_init=10 means "try 10 different starting positions, pick the best"

# .fit_predict() trains the model and returns cluster labels
clusters = kmeans.fit_predict(X_scaled)

# Add cluster labels to our data
df['cluster'] = clusters

# --- Analyze the clusters ---
print("Cluster profiles (mean values):")
print("=" * 55)

# .groupby('cluster').mean() calculates the average of each feature per cluster
# This is like: SELECT cluster, avg(cpu), avg(conn), avg(disk) GROUP BY cluster
profile = df.groupby('cluster')[['cpu_percent', 'connections', 'disk_percent']].mean()

for cluster_id in sorted(df['cluster'].unique()):
    row = profile.loc[cluster_id]
    count = (df['cluster'] == cluster_id).sum()
    print(f"\nCluster {cluster_id} ({count} servers):")
    print(f"  Avg CPU:         {row['cpu_percent']:.1f}%")
    print(f"  Avg Connections: {row['connections']:.0f}")
    print(f"  Avg Disk:        {row['disk_percent']:.1f}%")

    # Interpret the cluster based on its profile
    if row['connections'] > 100:
        print(f"  -> Looks like: OLTP (high connections)")
    elif row['cpu_percent'] > 70:
        print(f"  -> Looks like: OLAP (high CPU, low connections)")
    else:
        print(f"  -> Looks like: Idle (low everything)")

print()
print("K-Means discovered the 3 server types without being told!")
PYEOF
```

Expected output (yours will differ):
```
150 servers, 3 features each
We DON'T know there are 3 types. The algorithm will discover them.

Before scaling - mean: [53.3 75.  41.7]
After scaling  - mean: [-0.  -0.  -0. ]

Cluster profiles (mean values):
=======================================================

Cluster 0 (50 servers):
  Avg CPU:         85.4%
  Avg Connections: 19
  Avg Disk:        75.2%
  -> Looks like: OLAP (high CPU, low connections)

Cluster 1 (50 servers):
  Avg CPU:         14.7%
  Avg Connections: 5
  Avg Disk:        20.0%
  -> Looks like: Idle (low everything)

Cluster 2 (50 servers):
  Avg CPU:         59.8%
  Avg Connections: 201
  Avg Disk:        30.1%
  -> Looks like: OLTP (high connections)

K-Means discovered the 3 server types without being told!
```

---

## Step 3. Finding the right K (elbow method)

How do you know how many clusters to use? The elbow method tries different values of K and picks the "elbow" in the curve.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

# --- Same data ---
np.random.seed(42)
oltp = np.column_stack([np.random.normal(60, 10, 50), np.random.normal(200, 30, 50), np.random.normal(30, 5, 50)])
olap = np.column_stack([np.random.normal(85, 8, 50), np.random.normal(20, 10, 50), np.random.normal(75, 10, 50)])
idle = np.column_stack([np.random.normal(15, 5, 50), np.random.normal(5, 3, 50), np.random.normal(20, 5, 50)])
data = np.vstack([oltp, olap, idle])
df = pd.DataFrame(data, columns=['cpu_percent', 'connections', 'disk_percent'])

scaler = StandardScaler()
X_scaled = scaler.fit_transform(df)

# --- Elbow method ---
# Try K from 1 to 8
# For each K, measure "inertia" (sum of distances from each point to its cluster center)
# Lower inertia = tighter clusters = better
# But more clusters always gives lower inertia (K=150 would be "perfect" but useless)
# The "elbow" is where adding more clusters stops helping much

print("Elbow Method: finding the right number of clusters")
print("=" * 55)
print(f"{'K':>3s}  {'Inertia':>10s}  {'Decrease':>10s}  Chart")
print("-" * 55)

inertias = []
for k in range(1, 9):
    km = KMeans(n_clusters=k, random_state=42, n_init=10)
    km.fit(X_scaled)
    inertias.append(km.inertia_)

    # Calculate how much inertia decreased from the previous K
    if k > 1:
        decrease = inertias[-2] - inertias[-1]
        decrease_pct = decrease / inertias[-2] * 100
    else:
        decrease = 0
        decrease_pct = 0

    # Visual bar
    bar_width = int(inertias[-1] / inertias[0] * 40)
    bar = "#" * bar_width

    elbow = " <- ELBOW" if k == 3 else ""
    print(f"{k:>3d}  {inertias[-1]:>10.1f}  {decrease_pct:>9.1f}%  {bar}{elbow}")

print()
print("Reading the elbow chart:")
print("  K=1: Everything in one group (high inertia)")
print("  K=2: Big improvement (inertia drops a lot)")
print("  K=3: Big improvement (still worth adding a cluster)")
print("  K=4: Small improvement (not worth the extra cluster)")
print("  The 'elbow' is at K=3 - after that, improvements are small")
print()
print("K=3 matches the 3 server types we simulated!")
PYEOF
```

Expected output (yours will differ):
```
Elbow Method: finding the right number of clusters
=======================================================
  K     Inertia    Decrease  Chart
-------------------------------------------------------
  1       450.0       0.0%  ########################################
  2       243.7      45.8%  #####################
  3        81.2      66.7%  ####### <- ELBOW
  4        64.8      20.2%  #####
  5        53.1      18.0%  ####
  6        44.2      16.8%  ###
  7        37.5      15.2%  ###
  8        32.1      14.4%  ##

Reading the elbow chart:
  K=1: Everything in one group (high inertia)
  K=2: Big improvement (inertia drops a lot)
  K=3: Big improvement (still worth adding a cluster)
  K=4: Small improvement (not worth the extra cluster)
  The 'elbow' is at K=3 - after that, improvements are small

K=3 matches the 3 server types we simulated!
```

---

## Step 4. Using clusters for anomaly detection

Servers far from any cluster center are anomalies - they don't fit any known pattern.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

# --- Same data + some anomalies ---
np.random.seed(42)
oltp = np.column_stack([np.random.normal(60, 10, 50), np.random.normal(200, 30, 50), np.random.normal(30, 5, 50)])
olap = np.column_stack([np.random.normal(85, 8, 50), np.random.normal(20, 10, 50), np.random.normal(75, 10, 50)])
idle = np.column_stack([np.random.normal(15, 5, 50), np.random.normal(5, 3, 50), np.random.normal(20, 5, 50)])

# Add 5 weird servers that don't fit any pattern
# These are anomalies: high CPU AND high connections AND high disk
anomalies = np.array([
    [95, 280, 92],
    [98, 295, 88],
    [92, 260, 95],
    [97, 290, 90],
    [94, 275, 91],
])

data = np.vstack([oltp, olap, idle, anomalies])
df = pd.DataFrame(data, columns=['cpu_percent', 'connections', 'disk_percent'])

# Mark which ones are anomalies (for verification later)
df['is_anomaly'] = [False] * 150 + [True] * 5

scaler = StandardScaler()
X_scaled = scaler.fit_transform(df[['cpu_percent', 'connections', 'disk_percent']])

# Cluster
kmeans = KMeans(n_clusters=3, random_state=42, n_init=10)
clusters = kmeans.fit_predict(X_scaled)
df['cluster'] = clusters

# --- Calculate distance from cluster center ---
# Servers far from their cluster center are anomalous
# .transform() returns the distance to each cluster center
distances = kmeans.transform(X_scaled)

# For each server, get the distance to its ASSIGNED cluster center
# np.min(distances, axis=1) gets the distance to the nearest center
df['distance_to_center'] = np.min(distances, axis=1)

# --- Find anomalies ---
# Use a threshold: anything > 2 standard deviations from the mean distance
mean_dist = df['distance_to_center'].mean()
std_dist = df['distance_to_center'].std()
threshold = mean_dist + 2 * std_dist

df['flagged_anomaly'] = df['distance_to_center'] > threshold

print("Anomaly Detection Using Clustering")
print("=" * 60)
print(f"Distance threshold: {threshold:.3f} (mean + 2*std)")
print()

# Show the flagged anomalies
flagged = df[df['flagged_anomaly']].sort_values('distance_to_center', ascending=False)
print(f"Flagged {len(flagged)} anomalies:")
for _, row in flagged.iterrows():
    real = "REAL anomaly" if row['is_anomaly'] else "false alarm"
    print(f"  CPU={row['cpu_percent']:.0f}%, Conn={row['connections']:.0f}, "
          f"Disk={row['disk_percent']:.0f}%, Distance={row['distance_to_center']:.3f} ({real})")

print()

# Check accuracy
real_anomalies = df['is_anomaly'].sum()
detected = df[df['flagged_anomaly'] & df['is_anomaly']].shape[0]
false_alarms = df[df['flagged_anomaly'] & ~df['is_anomaly']].shape[0]
print(f"Real anomalies: {real_anomalies}")
print(f"Detected: {detected}/{real_anomalies}")
print(f"False alarms: {false_alarms}")
print()
print("The clustering-based approach found the weird servers")
print("without being told what 'weird' looks like!")
PYEOF
```

Expected output (yours will differ):
```
Anomaly Detection Using Clustering
============================================================
Distance threshold: 2.847 (mean + 2*std)

Flagged 5 anomalies:
  CPU=98%, Conn=295, Disk=88%, Distance=3.542 (REAL anomaly)
  CPU=97%, Conn=290, Disk=90%, Distance=3.501 (REAL anomaly)
  CPU=95%, Conn=280, Disk=92%, Distance=3.456 (REAL anomaly)
  CPU=94%, Conn=275, Disk=91%, Distance=3.389 (REAL anomaly)
  CPU=92%, Conn=260, Disk=95%, Distance=3.247 (REAL anomaly)

Real anomalies: 5
Detected: 5/5
False alarms: 0

The clustering-based approach found the weird servers
without being told what 'weird' looks like!
```

---

## What You Learned

| Concept | What It Is | DBA Analogy |
|---------|-----------|-------------|
| Unsupervised learning | No labels - find patterns automatically | "Find groups in this data" |
| K-Means | Assigns each point to the nearest cluster center | GROUP BY similarity |
| StandardScaler | Z-score normalization before clustering | Must normalize - distance-based |
| Elbow method | Try different K, pick the "elbow" | Finding the right number of groups |
| Inertia | Sum of distances to cluster centers | Lower = tighter clusters |
| Anomaly detection | Far from any cluster center = anomaly | "This server doesn't fit any pattern" |
| .fit_predict() | Train and get cluster labels in one step | Cluster assignment |
| .transform() | Get distance to each cluster center | Measure how "normal" a point is |
