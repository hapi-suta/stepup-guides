# Concepts: Classical Machine Learning

## What Is Machine Learning?

Machine learning is teaching a computer to make predictions from data - without writing explicit rules.

As a DBA, you write rules by hand:
```sql
-- Hand-written rule: flag slow queries
SELECT * FROM pg_stat_activity
WHERE state = 'active' AND duration > interval '5 minutes';
```

Machine learning flips this. Instead of writing the rule, you give the computer examples and it figures out the rule itself:

```
Training data:
  CPU=92%, Connections=285, Disk=91%  -> incident
  CPU=15%, Connections=25,  Disk=30%  -> healthy
  CPU=88%, Connections=270, Disk=85%  -> incident
  CPU=20%, Connections=40,  Disk=35%  -> healthy
  ... (hundreds more examples)

Model learns: "When CPU > 80% AND connections > 200, predict incident"
```

You didn't write that rule. The model discovered it from the data.

## Why "Classical" ML?

"Classical" means algorithms that existed before deep learning (neural networks) took over. They're simpler, faster to train, and often work just as well when you don't have millions of data points.

| | Classical ML | Deep Learning |
|---|---|---|
| Data needed | Hundreds to thousands | Thousands to millions |
| Training time | Seconds to minutes | Hours to days |
| Interpretability | Often explainable | Black box |
| Hardware | Laptop CPU | GPU required |
| Best for | Structured/tabular data | Images, text, audio |

**Key insight:** Most real-world business data is tabular (rows and columns in a database). For tabular data, classical ML often beats deep learning. As a DBA, most of your data is tabular - so classical ML is your sweet spot.

## The ML Workflow

Every ML project follows the same steps:

```
1. GET DATA        ->  SELECT * FROM metrics_history
2. PREPARE DATA    ->  Clean, normalize, split into train/test
3. CHOOSE MODEL    ->  Linear regression? Decision tree? Random forest?
4. TRAIN           ->  model.fit(X_train, y_train)
5. EVALUATE        ->  model.score(X_test, y_test)
6. PREDICT         ->  model.predict(new_data)
```

This is the same every time. The only thing that changes is step 3 (which algorithm).

## The Algorithms You'll Learn

### Linear Regression - "Draw a Line"
Predicts a number. Like: "Given these server metrics, what will the query time be?"
- Input: numbers (features)
- Output: a number (prediction)
- DBA analogy: Like trend lines in Grafana dashboards

### Logistic Regression - "Yes or No?"
Predicts a category (usually yes/no). Like: "Will this server have an incident today?"
- Input: numbers (features)
- Output: probability (0 to 1)
- DBA analogy: Like a health check that returns pass/fail

### Decision Trees - "A Flowchart"
Makes decisions by asking yes/no questions. Like a troubleshooting runbook.
- Input: numbers or categories
- Output: a prediction (number or category)
- DBA analogy: Literally a runbook: "Is CPU > 80%? Yes -> Check connections. Connections > 200? Yes -> Alert."

### Random Forest - "Ask 100 Experts"
Builds many decision trees and takes a vote. More accurate than a single tree.
- Input: numbers or categories
- Output: majority vote from all trees
- DBA analogy: Like asking 100 DBAs and going with the majority opinion

### K-Means Clustering - "Group Similar Things"
Finds groups in your data without labels. Like: "Which servers behave similarly?"
- Input: numbers (features)
- Output: group assignment (cluster 0, 1, 2, ...)
- DBA analogy: Like grouping servers by workload pattern (OLTP, OLAP, idle)

## Key Concepts

### Features vs Labels
- **Features** (X): The input columns. What you know. Like CPU, memory, connections.
- **Labels** (y): What you're predicting. Like "incident" or "healthy."
- In SQL: features = WHERE clause columns, label = the column you're trying to predict.

### Train/Test Split
- Split your data: 80% for training, 20% for testing
- Train on 80%. Test on 20% the model has NEVER seen.
- This prevents cheating - the model can't just memorize the answers.
- DBA analogy: Like testing a backup restore on a different server, not the one you backed up from.

### Overfitting vs Underfitting
- **Overfitting**: Model memorized the training data but fails on new data. Like studying the answer key instead of learning the material.
- **Underfitting**: Model is too simple to capture the pattern. Like using `SELECT count(*)` to diagnose a complex performance issue.
- Goal: good performance on data the model has never seen.

### Evaluation Metrics
- **Accuracy**: What % of predictions are correct? (misleading with imbalanced data)
- **Precision**: When the model says "incident," how often is it right?
- **Recall**: Of all real incidents, how many did the model catch?
- **F1 Score**: Balance between precision and recall
- **MSE**: Average squared error for regression (predicting numbers)

## What You'll Build

| Build | Algorithm | What You'll Predict |
|-------|-----------|-------------------|
| 01 | ML Workflow + Linear Regression | Query time from server metrics |
| 02 | Logistic Regression + Decision Tree | Server incident yes/no |
| 03 | Random Forest + Evaluation | Best model with proper metrics |
| 04 | K-Means Clustering | Server workload groups |
