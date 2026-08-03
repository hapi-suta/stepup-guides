# Evaluation & Testing - Concepts

Building an AI model is half the job. Knowing if it actually works - and continues to work - is the other half. This module teaches you how to measure, test, and monitor AI systems like you already do with databases.

---

## Why Should You Care?

A model with 95% accuracy sounds great until:
- It misses 100% of critical database alerts (the 5% are all critical ones)
- It gives confident wrong answers that your team trusts
- Performance degrades silently over months as data patterns shift
- You can't explain to management why the model made a specific decision

Evaluation is how you prevent these disasters. It's the `pg_stat_statements` of AI.

---

## The DBA Analogy

| Database Monitoring | AI Evaluation |
|-------------------|---------------|
| pg_stat_statements (query performance) | Metrics (accuracy, F1, RMSE) |
| EXPLAIN ANALYZE (query plan) | Explainability (why did the model predict this?) |
| pg_stat_user_tables (table health) | Data drift detection (has input data changed?) |
| WAL monitoring (replication health) | Model drift (is the model getting worse?) |
| pg_stat_activity (current state) | Inference monitoring (latency, throughput, errors) |
| Automated alerts (disk full, lag) | Automated model alerts (accuracy drop, drift) |

You already know how to monitor systems. AI evaluation uses the same principles with different metrics.

---

## Key Concepts

### 1. Classification Metrics

For models that predict categories (healthy/incident, alert type):

| Metric | What It Measures | When It Matters |
|--------|-----------------|-----------------|
| Accuracy | % of correct predictions | Balanced datasets only |
| Precision | Of predicted positives, how many are correct? | When false alarms are costly |
| Recall | Of actual positives, how many were found? | When missing events is costly |
| F1 Score | Balance between precision and recall | Most situations |
| AUC-ROC | Overall ranking quality | Comparing models |

**DBA rule of thumb:**
- Alert system: prioritize **recall** (don't miss real incidents)
- Automated action system: prioritize **precision** (don't take wrong action)

### 2. Regression Metrics

For models that predict numbers (query time, CPU usage):

| Metric | What It Measures |
|--------|-----------------|
| RMSE | Average error magnitude (in same units as target) |
| MAE | Average absolute error (less sensitive to outliers) |
| R2 | How much variance is explained (0 = random, 1 = perfect) |
| MAPE | Error as percentage of actual value |

### 3. LLM Evaluation

For text generation (chatbots, text-to-SQL):

| Approach | What It Measures |
|----------|-----------------|
| BLEU/ROUGE | Text overlap with reference answer |
| Human evaluation | Quality, accuracy, helpfulness (gold standard) |
| LLM-as-judge | Use a stronger model to evaluate a weaker one |
| Task-specific tests | Does the SQL actually run? Is the answer factually correct? |

### 4. Monitoring in Production

| What to Monitor | Why |
|----------------|-----|
| Input data distribution | Detect if real data looks different from training data |
| Prediction distribution | Detect if model outputs shift (always predicting one class) |
| Latency | Ensure model responds within SLA |
| Error rate | Catch crashes, timeouts, malformed outputs |
| Feature drift | Individual features changing over time |

---

## What You'll Build

| Build | What | Why |
|-------|------|-----|
| 01 - Classification Metrics Deep Dive | Precision, recall, F1, confusion matrix, threshold tuning | Know exactly how your model fails |
| 02 - Regression and Calibration | RMSE, MAE, R2, calibration plots | Evaluate numeric predictions and confidence |
| 03 - Testing AI Systems | Unit tests, integration tests, behavioral tests | Catch bugs before deployment |
| 04 - Monitoring and Drift Detection | Data drift, model drift, production alerts | Keep models working after deployment |
