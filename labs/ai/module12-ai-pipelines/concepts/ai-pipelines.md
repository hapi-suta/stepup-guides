# AI Pipelines - Concepts

An AI pipeline connects all the pieces you've learned into one automated workflow: data collection, preprocessing, embedding generation, model inference, and result delivery. Instead of running scripts manually, you build a system that runs end-to-end.

---

## Why Should You Care?

In production, AI isn't a Jupyter notebook you run once. It's a pipeline that:
- Ingests new database alerts every minute
- Preprocesses and validates input data
- Generates embeddings or runs inference
- Stores results and triggers actions
- Handles errors gracefully
- Logs everything for debugging

Without pipelines, your AI is a demo. With pipelines, it's a product.

---

## The DBA Analogy

| PostgreSQL Pipeline | AI Pipeline |
|-------------------|-------------|
| pg_cron job that runs VACUUM | Scheduled pipeline that retrains a model |
| ETL: Extract -> Transform -> Load | Data -> Preprocess -> Embed -> Store |
| Streaming replication (continuous) | Streaming inference (real-time predictions) |
| pg_dump -> S3 -> restore (batch) | Batch prediction -> store results |
| pgAgent job chain | Pipeline DAG (directed acyclic graph) |
| Error handling in plpgsql | Error handling in pipeline stages |

You already build data pipelines for PostgreSQL. AI pipelines follow the same patterns with different components.

---

## Key Concepts

### 1. Pipeline Types

**Batch pipeline:** Process data in chunks on a schedule.
- Run every hour/day
- Process all new data since last run
- Good for: model retraining, bulk embedding generation, report generation

**Streaming pipeline:** Process data as it arrives.
- Run continuously
- Process each event immediately
- Good for: real-time alert classification, live anomaly detection

**Hybrid:** Streaming for inference, batch for retraining.
- Most production systems use this pattern

### 2. Pipeline Stages

A typical AI pipeline has these stages:

```
[1] Ingest     -> Collect raw data (logs, alerts, metrics)
[2] Validate   -> Check data quality (no NaN, correct format)
[3] Transform  -> Preprocess (normalize, tokenize, embed)
[4] Predict    -> Run model inference
[5] Post-proc  -> Format results, apply thresholds
[6] Store      -> Save results to database/API
[7] Act        -> Trigger alerts, update dashboards
```

### 3. Error Handling

Each stage can fail. A production pipeline handles:
- **Retries:** Transient failures (network timeout, API rate limit)
- **Dead letter queue:** Permanently failed items saved for investigation
- **Fallback:** If the model fails, use a rule-based backup
- **Monitoring:** Track success/failure rates per stage

### 4. Pipeline Orchestration

Tools that manage pipeline execution:
- **Simple:** Python scripts with scheduling (cron, pg_cron)
- **Medium:** Luigi, Prefect, Dagster
- **Complex:** Apache Airflow, Kubeflow

For most DBA use cases, Python scripts with proper error handling are sufficient.

---

## What You'll Build

| Build | What | Why |
|-------|------|-----|
| 01 - Building Pipeline Stages | Individual stages with validation | Foundation - clean, testable components |
| 02 - Batch Pipeline | End-to-end batch processing | Process data on a schedule |
| 03 - Streaming Pipeline | Real-time event processing | Handle events as they arrive |
| 04 - Error Handling and Monitoring | Retries, dead letters, logging | Production reliability |
