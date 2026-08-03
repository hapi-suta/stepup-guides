# Interview 01: AI Pipeline Questions

---

## Question 1: Batch vs Streaming - when do you use each?

**What they're asking:** Can you pick the right pipeline architecture for a given scenario?

**Answer:**

Batch pipelines process accumulated data on a schedule. Use batch when:
- Latency tolerance is minutes to hours (daily reports, model retraining)
- Processing is expensive and benefits from bulk operations (batch embeddings are 25x faster than one-at-a-time)
- Data arrives in chunks (log files, CSV imports)

Streaming pipelines process each event immediately. Use streaming when:
- Latency tolerance is seconds (real-time alert classification, anomaly detection)
- Each event needs immediate action (page on-call, trigger failover)
- Events arrive continuously (monitoring metrics)

Most production systems use hybrid - streaming for inference (classify alerts in real time), batch for training (retrain the model weekly).

**DBA parallel:** Batch is like pg_cron running VACUUM every night. Streaming is like a trigger that fires on every INSERT. You wouldn't VACUUM on every insert, and you wouldn't wait until midnight to detect a critical alert.

---

## Question 2: How do you handle failures in an AI pipeline?

**What they're asking:** Do you build resilient systems, or pipelines that crash on the first error?

**Answer:**

Three-layer defense:

1. **Retry with exponential backoff** for transient failures (network timeout, rate limit). Wait 1s, 2s, 4s between retries. Add jitter (random delay) to prevent thundering herd - where all clients retry at the exact same time and overwhelm the recovering service.

2. **Dead letter queue (DLQ)** for permanent failures. When an item fails after all retries, save it with the original data, error message, timestamp, and failure stage. Review DLQ items manually or replay them after fixing the bug.

3. **Per-item isolation** - one bad item must not crash the entire batch. Wrap each item's processing in try/except so the other 999 items still get processed.

Key distinction: only retry transient failures (timeout, connection error). Don't retry permanent failures (invalid data, auth error) - they'll fail every time and waste resources.

**DBA parallel:** Retries are like connection pooler retry logic. DLQ is like an error log table. Per-item isolation is like using SAVEPOINT so one bad row doesn't abort the whole transaction.

---

## Question 3: What is a poison pill and how do you prevent it?

**What they're asking:** Have you dealt with real production pipeline failures?

**Answer:**

A poison pill is a single malformed message that crashes the pipeline every time it's processed. The pipeline restarts, picks up the same message, crashes again - an infinite crash loop. Meanwhile, hundreds of valid messages are stuck behind it.

Prevention:

1. **Input validation before processing** - check types (is message actually a string?), check required fields, check value ranges. Reject bad data before it reaches the processing logic.

2. **Per-item error handling** - wrap each item in try/except. If one item fails, send it to the DLQ and continue with the next item.

3. **Poison pill detection** - track how many times each item has failed. If an item fails more than N times, auto-quarantine it (skip it permanently and alert an engineer).

4. **Progressive queue clearing** - don't process the entire queue as one atomic operation. Mark items as "processing" or "done" individually, so a crash doesn't replay the entire queue.

**DBA parallel:** Like a trigger function that crashes on one specific row pattern. Every new INSERT on that table fails. Fix: add validation in the trigger, or use a WHERE clause to skip the problem row.

---

## Question 4: How do you monitor an AI pipeline in production?

**What they're asking:** Do you just check if it's running, or do you have real observability?

**Answer:**

Three types of monitoring:

1. **Error monitoring** - track success/failure count per stage. Alert when failure rate exceeds threshold (e.g., > 5% failures). Track error types to spot patterns.

2. **Liveness monitoring** - check that each stage has run recently. "No errors" does NOT mean healthy - the stage might have stopped running entirely. A growing queue with zero errors means the consumer is stalled. This catches silent stalls that error monitoring misses.

3. **Performance monitoring** - track latency per stage (average, p95, p99). Track throughput (items processed per hour). Alert when latency exceeds SLA or throughput drops below baseline.

Key metrics dashboard:
- Success rate per stage (target: > 95%)
- Average latency per stage
- Queue depth over time (should stay flat or decrease, never grow continuously)
- DLQ size (growing DLQ = systemic problem, not just random failures)
- Last run time per stage (liveness check)

**DBA parallel:** Like combining pg_stat_statements (performance), pg_stat_replication (liveness), and error logs (failures). You wouldn't monitor replication by just checking "is the connection up" - you'd check "is the replay LSN advancing."

---

## Question 5: Walk me through designing a pipeline for classifying database alerts.

**What they're asking:** Can you design a complete system, not just write code for one piece?

**Answer:**

Pipeline stages:

1. **Ingest** - Collect alerts from monitoring systems (Prometheus, Grafana, Nagios). Accept multiple formats (JSON, string, webhook). Parse into a standard internal format with required fields: message, severity, source, timestamp.

2. **Validate** - Check required fields exist. Verify severity is a valid value. Reject empty messages. Separate valid alerts from invalid ones. Invalid alerts go to DLQ.

3. **Transform** - Normalize text (lowercase, strip whitespace). Map severity to numeric score. Add computed fields (message length, source category). This ensures the classifier sees consistent input.

4. **Classify** - Primary: ML model (e.g., fine-tuned BERT) classifies into categories (performance, storage, replication, security). Fallback: keyword-based rules if model is unavailable. Output: category + confidence score.

5. **Store** - Write classified alerts to PostgreSQL. Include original data + classification + metadata. Use batch INSERT for efficiency.

6. **Act** - Route critical alerts to PagerDuty. Update Grafana dashboard. Send daily summary report.

Architecture choices:
- **Streaming** for classification (alerts need immediate routing)
- **Batch** for model retraining (weekly, using accumulated labeled data)
- PostgreSQL LISTEN/NOTIFY for simple real-time events (no Kafka needed for most DBA use cases)
- Retry with backoff on the classify stage (model service might be temporarily down)
- DLQ for validation failures and persistent classification failures
- Liveness monitoring on every stage

**DBA parallel:** This is an ETL pipeline. Ingest = COPY FROM, Validate = CHECK constraints, Transform = data type casting, Classify = function call, Store = INSERT, Act = pg_notify + triggers.
