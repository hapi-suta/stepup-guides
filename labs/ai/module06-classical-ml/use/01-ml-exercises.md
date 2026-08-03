# USE 01: Classical ML Exercises

Practice what you built. Each exercise reinforces a concept from Builds 01-04.

---

## Exercise 1: Predict Database Size Growth (Linear Regression)

Build a model that predicts how large a database will be next month.

**Setup data:**
```python
import numpy as np
import pandas as pd
np.random.seed(42)

# 50 databases tracked monthly
n = 50
current_size_gb = np.random.uniform(1, 500, n)
daily_inserts = np.random.uniform(1000, 1_000_000, n)
avg_row_bytes = np.random.uniform(100, 2000, n)
retention_days = np.random.uniform(30, 365, n)

# Next month's size depends on current size + incoming data
next_month_gb = (current_size_gb +
                 daily_inserts * avg_row_bytes * 30 / (1024**3) +
                 np.random.normal(0, 5, n))
```

**Task:**
1. Create a DataFrame with features and label
2. Train/test split (80/20)
3. Train a LinearRegression model
4. Print the R2 score and RMSE
5. Print the learned weights and interpret: which feature matters most for growth?
6. Predict the size next month for a database with: current=100GB, 500K inserts/day, 500 byte rows, 90-day retention

---

## Exercise 2: Alert Priority Classifier (Logistic Regression vs Decision Tree)

Build a model that classifies database alerts as "critical" or "low priority."

**Setup data:**
```python
import numpy as np
import pandas as pd
np.random.seed(42)

n = 400
cpu = np.random.uniform(10, 99, n)
replication_lag_sec = np.random.uniform(0, 300, n)
connection_pct = np.random.uniform(5, 100, n)  # % of max_connections
disk_pct = np.random.uniform(10, 99, n)

# Critical if: any resource is severely exhausted
critical = (
    (cpu > 90) | (replication_lag_sec > 120) |
    (connection_pct > 90) | (disk_pct > 90)
).astype(int)
```

**Task:**
1. Train both LogisticRegression and DecisionTreeClassifier
2. Compare accuracy, precision, recall, and F1 on the test set
3. Print the decision tree rules (export_text)
4. Which model has better recall? (For alerts, recall matters most - don't miss critical events)
5. Print feature importance from the decision tree

---

## Exercise 3: Model Selection with Cross-Validation (Random Forest)

Compare 5 models using proper cross-validation to find the best one.

**Task:**
1. Use the data from Exercise 2
2. Train and evaluate these 5 models with 5-fold cross-validation:
   - LogisticRegression
   - DecisionTreeClassifier(max_depth=3)
   - DecisionTreeClassifier(max_depth=6)
   - RandomForestClassifier(n_estimators=50)
   - RandomForestClassifier(n_estimators=200)
3. Print a table showing: model name, mean F1, std F1
4. Pick the best model based on highest mean F1 with lowest std
5. Train the best model on the full training set and show the confusion matrix

---

## Exercise 4: Server Workload Clustering (K-Means)

Cluster 200 servers into workload groups and profile each group.

**Setup data:**
```python
import numpy as np
np.random.seed(42)

# 200 servers with mixed workloads
n = 200
cpu = np.random.uniform(5, 99, n)
memory = np.random.uniform(10, 99, n)
read_iops = np.random.uniform(10, 50000, n)
write_iops = np.random.uniform(10, 30000, n)
connections = np.random.uniform(1, 500, n)
```

**Task:**
1. Normalize the data with StandardScaler
2. Use the elbow method to find the optimal K (try K=2 through K=8)
3. Cluster with the optimal K
4. Profile each cluster: print mean values and assign a label (e.g., "Read-heavy OLAP", "Write-heavy OLTP", "Idle", etc.)
5. Add 3 anomalous servers and use the distance-from-center method to detect them

---

## Exercise 5: End-to-End ML Pipeline

Build a complete ML pipeline from raw data to prediction.

**Task:**
1. Generate 500 rows of server data with 8 features
2. Add realistic noise: 5% missing values, some outliers
3. Clean the data: fill missing values, handle outliers
4. Normalize features
5. Train/test split
6. Train 3 different models (your choice)
7. Evaluate with cross-validation
8. Pick the best model
9. Make predictions for 5 new servers
10. Print a complete report: data summary, model comparison, predictions

This is the pattern you'll use for every real ML project.

---

## Scoring Guide

| Exercise | Skill Tested | Difficulty |
|----------|-------------|------------|
| 1 | Linear regression, interpretation | Beginner |
| 2 | Classification comparison, recall | Beginner |
| 3 | Cross-validation, model selection | Intermediate |
| 4 | Clustering, profiling, anomaly detection | Intermediate |
| 5 | Full pipeline from scratch | Advanced |
