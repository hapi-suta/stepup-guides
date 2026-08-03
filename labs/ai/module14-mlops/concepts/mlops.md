# MLOps - Concepts

MLOps is DevOps for machine learning. It's the discipline of deploying, monitoring, and maintaining ML models in production reliably and at scale. You already do this for databases - MLOps applies the same rigor to models.

---

## Why Should You Care?

Building a model is 20% of the work. Keeping it running, accurate, and reliable in production is the other 80%. Without MLOps:
- Nobody knows which model version is in production
- Models degrade silently as data changes
- Retraining is manual and error-prone
- There's no way to reproduce a model from 3 months ago
- Debugging a bad prediction is a guessing game

With MLOps, your ML system is as reliable as your PostgreSQL cluster.

---

## The DBA Analogy

| Database Operations | MLOps |
|--------------------|-------|
| Database backups & PITR | Model versioning & reproducibility |
| Schema migrations | Data pipeline versioning |
| Monitoring (pg_stat_*) | Model performance tracking |
| Automated failover | Automated model rollback |
| CI/CD for SQL changes | CI/CD for model training + deployment |
| Change management | Experiment tracking |
| Runbooks for incidents | Runbooks for model degradation |
| Data validation (CHECK constraints) | Data validation (schema checks, drift detection) |
| pg_cron scheduled jobs | Automated retraining pipelines |
| Audit logging | Prediction logging & lineage |

You already practice most of MLOps - you just call it "database operations."

---

## Key Concepts

### 1. The ML Lifecycle

```
[1] Data Collection    -> Gather training data
[2] Data Validation    -> Check data quality
[3] Feature Engineering -> Create model inputs
[4] Model Training     -> Train the model
[5] Model Evaluation   -> Test accuracy
[6] Model Deployment   -> Serve predictions
[7] Model Monitoring   -> Track performance
[8] Retraining         -> Update when degraded
```

MLOps automates and connects all 8 stages.

### 2. Experiment Tracking

Every training run should record:
- What data was used (version, size, splits)
- What hyperparameters were set (learning rate, epochs, batch size)
- What metrics were achieved (accuracy, F1, loss)
- What code version was used (git commit)

Tools: MLflow, Weights & Biases, simple JSON logs.

### 3. Data Versioning

Models are only as good as their training data. Track:
- Which version of the dataset was used
- When it was created
- What transformations were applied
- How it was split (train/test/val)

DBA analogy: like tracking which pg_dump version was used to seed a test database.

### 4. CI/CD for ML

Continuous Integration:
- Run data validation checks on new data
- Run model tests (unit tests, behavioral tests)
- Compare new model accuracy against baseline

Continuous Deployment:
- Deploy new model if it passes all checks
- Use shadow mode or A/B testing for safety
- Auto-rollback if metrics degrade

### 5. Feature Stores

A feature store is a central repository of computed features used by models. Instead of each model computing "average CPU over last hour" independently, a feature store computes it once and serves it to all models.

DBA analogy: materialized views. Instead of every query recomputing the same aggregation, a materialized view stores the pre-computed result.

### 6. Model Governance

For regulated environments:
- Who trained the model?
- What data was it trained on?
- What decisions does it make?
- Can we explain its predictions?
- Is there bias in the training data?

DBA analogy: audit logging for compliance (who accessed what data, when).

---

## What You'll Build

| Build | What | Why |
|-------|------|-----|
| 01 - Experiment Tracking | Log and compare training runs | Know what works and reproduce it |
| 02 - Data Versioning | Track dataset versions and lineage | Reproduce any model |
| 03 - CI/CD for ML | Automated testing and deployment | Deploy models safely |
| 04 - Automated Retraining | Trigger retraining on schedule or drift | Keep models fresh |
