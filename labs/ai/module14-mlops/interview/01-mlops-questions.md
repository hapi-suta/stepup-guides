# Interview 01: MLOps Questions

---

## Question 1: What is MLOps and why does it matter?

**What they're asking:** Do you understand the operational side of ML, not just the modeling?

**Answer:**

MLOps is DevOps for machine learning - the practices and tools for deploying, monitoring, and maintaining ML models in production reliably.

Building a model is 20% of the work. The other 80% is:
- Versioning data and models so you can reproduce any result
- Testing automatically before deployment (accuracy thresholds, behavioral tests, regression checks)
- Monitoring in production (accuracy drift, data drift, latency)
- Retraining when the model degrades
- Rolling back when a new model is worse than the old one

Without MLOps, every model deployment is manual, error-prone, and unreproducible. With MLOps, deploying a model is as routine as deploying a code change.

**DBA parallel:** MLOps is database operations. You wouldn't run PostgreSQL without backups, monitoring, automated failover, and tested upgrade procedures. MLOps is the same discipline applied to models. Experiment tracking is pg_stat_statements. Data versioning is pg_dump. Automated retraining is autoanalyze. Rollback is PITR.

---

## Question 2: How do you ensure a model is reproducible?

**What they're asking:** Can you recreate a model from scratch if needed?

**Answer:**

A model is reproducible when you can recreate it exactly from its metadata. Five things must be recorded:

1. **Training data version** - hash the dataset so you can verify it's the same data. Store the exact data file or a pointer to it.

2. **Train/test split** - save the exact indices or random seed used. The same data with a different split produces a different model.

3. **Hyperparameters** - learning rate, epochs, batch size, model architecture, every setting. Use an experiment tracker.

4. **Code version** - git commit hash. The training script itself might change over time.

5. **Dependencies** - exact library versions (requirements.txt with pinned versions). PyTorch 2.0 and 2.1 can produce different results with the same code and data.

In practice: Docker containers are the best way to lock all of this together. Build a Docker image for each model version. Six months later, you can run that exact image and get the same model.

**DBA parallel:** Like documenting a database setup so someone else can recreate it. You'd record: PostgreSQL version, extensions, postgresql.conf, pg_hba.conf, schema, data. A model needs the same level of documentation.

---

## Question 3: How do you detect and handle model drift?

**What they're asking:** Do you know models degrade over time?

**Answer:**

Model drift is when a model's performance degrades because the real-world data has changed since training. Two types:

**Data drift** - the input data distribution changes. Example: your alert classifier was trained on on-premise PostgreSQL alerts. Your company migrates to cloud. Now the model sees "RDS connection timeout" and "Aurora failover" - patterns it never learned.

**Concept drift** - the relationship between inputs and outputs changes. Example: "WAL growth" used to mean "storage" category. After adopting streaming replication, "WAL growth" now often means "replication" category.

Detection methods:
- **Statistical tests** - compare recent data distribution to training data distribution (KS test for numeric features, chi-squared for categories)
- **Performance monitoring** - track accuracy on labeled production data. If accuracy drops below threshold, drift is happening.
- **Prediction distribution** - if the model starts predicting one category much more or less often, something changed.

Handling:
- **Scheduled retraining** - retrain every week/month with fresh data (simple, catches most drift)
- **Triggered retraining** - automatically retrain when drift detection fires or accuracy drops
- **Fallback** - if drift is extreme, fall back to rules-based classification while retraining

**DBA parallel:** Data drift is like PostgreSQL statistics going stale after a large data load. The query planner uses outdated stats and picks bad plans. ANALYZE updates the stats. Retraining updates the model. Autoanalyze triggers ANALYZE automatically when data changes - that's your drift-triggered retraining.

---

## Question 4: What's your CI/CD pipeline for ML models?

**What they're asking:** Do you have automated quality gates, or do you deploy by hand?

**Answer:**

The pipeline has three stages:

**Continuous Integration (on every code/data change):**
1. Data validation - check data quality (no empty rows, valid categories, no leakage between train/test)
2. Train model - run training with the latest data
3. Model tests - accuracy threshold (>85%), behavioral tests (known patterns classified correctly), no regression vs production model, latency check (p95 < 100ms)

**Continuous Deployment (on main branch, after CI passes):**
1. Deploy to shadow mode - new model runs alongside production but doesn't serve results
2. Compare shadow vs production for 24 hours
3. If shadow is better: promote to A/B test (10% traffic)
4. If A/B is better: gradually increase to 100%
5. If anything fails: automatic rollback to previous version

**Automated Retraining (scheduled or triggered):**
1. Weekly: collect new labeled data, retrain, run CI
2. On drift detection: trigger retraining immediately
3. On accuracy drop: alert team + trigger retraining

Tools: GitHub Actions for CI/CD, model registry for versioning, Prometheus/Grafana for monitoring.

**DBA parallel:** This is the same as CI/CD for database migrations. Test on staging (shadow mode), apply gradually (A/B), monitor (pg_stat_statements), rollback if bad (PITR). The same operational rigor applies.

---

## Question 5: What would you do if you discovered the test set was included in training data?

**What they're asking:** Can you handle a real-world MLOps incident?

**Answer:**

This is data contamination/leakage - the model memorized test answers instead of learning patterns. Immediate actions:

1. **Rollback** - switch production back to the previous model version (the one trained on clean data). This is a 5-minute fix using the model registry.

2. **Assess damage** - check production accuracy logs. If the contaminated model was deployed, real-world accuracy was likely much lower than the 99% test accuracy suggested. Calculate how long it was live and how many predictions were affected.

3. **Root cause** - find the data export script that included test data in training. Usually it's a missing WHERE clause or a re-split that included all data.

4. **Fix the pipeline** - add automated contamination checks that run before every training job: check for ID overlap between train and test, check for content hash overlap, flag suspiciously high accuracy (>95% is a warning).

5. **Add a hold-out set** - keep 5% of data that is NEVER used in any pipeline. If test accuracy is 99% but hold-out accuracy is 85%, contamination is likely.

6. **Retrain** - with the clean, properly split data. Deploy through the normal CI/CD pipeline with shadow mode.

Prevention: version your data splits (save the exact train/test indices), automate overlap detection, monitor real-world accuracy (not just test accuracy).

**DBA parallel:** Like discovering your backup verification was restoring to the same server. The "backup verified" status was meaningless. Fix: test backups by restoring to a different server. Add automated verification that compares source and target.
