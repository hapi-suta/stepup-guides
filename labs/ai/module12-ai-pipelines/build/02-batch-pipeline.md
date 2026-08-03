# Build 02: Batch Pipeline

A batch pipeline processes data in chunks on a schedule. This is the most common pattern: collect alerts for an hour, classify them all at once, store results. Efficient and simple.

---

## Step 1. Build a batch alert processor

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import os
import time
from datetime import datetime, timedelta
from pathlib import Path

print("""
Batch Pipeline: Process accumulated data at regular intervals.

How it works:
  1. Data accumulates in a queue (file, database table, message queue)
  2. Pipeline runs on a schedule (every 5 min, hourly, daily)
  3. Pipeline reads ALL pending data, processes it, marks as done
  4. Efficient: one model load, batch inference

DBA analogy:
  - Like a pg_cron job that processes new rows
  - SELECT * FROM alerts WHERE processed = FALSE
  - Process them in one batch
  - UPDATE alerts SET processed = TRUE
""")

# Simulate: alerts accumulate in a JSON file (queue)
queue_file = "/tmp/alert_queue.jsonl"
results_file = "/tmp/alert_results.jsonl"

# Generate some alerts (simulating accumulation over time)
alerts = [
    {"id": 1, "message": "CPU at 95% on pg-primary-1", "severity": "critical", "ts": "2024-01-15T10:00:00"},
    {"id": 2, "message": "Disk usage at 87% on /pgdata", "severity": "medium", "ts": "2024-01-15T10:01:00"},
    {"id": 3, "message": "Replication lag 60 seconds", "severity": "high", "ts": "2024-01-15T10:02:00"},
    {"id": 4, "message": "Failed login from 10.0.0.99", "severity": "high", "ts": "2024-01-15T10:03:00"},
    {"id": 5, "message": "Slow query: 45 seconds on orders", "severity": "medium", "ts": "2024-01-15T10:04:00"},
    {"id": 6, "message": "WAL directory growing fast", "severity": "high", "ts": "2024-01-15T10:05:00"},
    {"id": 7, "message": "Connection pool exhausted", "severity": "critical", "ts": "2024-01-15T10:06:00"},
    {"id": 8, "message": "SSL certificate expires in 3 days", "severity": "low", "ts": "2024-01-15T10:07:00"},
]

# Write alerts to queue file
with open(queue_file, "w") as f:
    for alert in alerts:
        f.write(json.dumps(alert) + "\n")
print(f"Queued {len(alerts)} alerts to {queue_file}")

# Batch processing function
def process_batch(queue_path, results_path):
    """Process all pending alerts in one batch."""
    start_time = time.time()

    # Read pending alerts
    pending = []
    with open(queue_path) as f:
        for line in f:
            line = line.strip()
            if line:
                pending.append(json.loads(line))

    if not pending:
        print("No pending alerts to process")
        return 0

    print(f"\nProcessing batch of {len(pending)} alerts...")

    # Classify (keyword-based; production would use a model)
    categories = {
        "performance": ["cpu", "slow", "query", "latency", "connection", "timeout"],
        "storage": ["disk", "space", "full", "wal", "bloat"],
        "replication": ["replication", "standby", "lag", "wal sender"],
        "security": ["login", "ssl", "password", "unauthorized", "access"],
    }

    results = []
    for alert in pending:
        msg = alert["message"].lower()
        scores = {c: sum(1 for k in kws if k in msg) for c, kws in categories.items()}
        category = max(scores, key=scores.get) if max(scores.values()) > 0 else "unknown"

        results.append({
            **alert,
            "category": category,
            "processed_at": datetime.now().isoformat(),
        })

    # Write results
    with open(results_path, "a") as f:
        # "a" = append mode (don't overwrite previous results)
        for result in results:
            f.write(json.dumps(result) + "\n")

    # Clear the queue (mark as processed)
    open(queue_path, "w").close()
    # Opening in "w" mode and immediately closing truncates the file

    duration = time.time() - start_time
    print(f"Processed {len(results)} alerts in {duration*1000:.1f}ms")
    print(f"Results saved to {results_path}")

    return len(results)

# Run the batch
processed = process_batch(queue_file, results_file)

# Show results
print(f"\nResults:")
print(f"{'ID':>4s}  {'Severity':>9s}  {'Category':>13s}  Message")
print("-" * 65)
with open(results_file) as f:
    for line in f:
        r = json.loads(line)
        print(f"{r['id']:>4d}  {r['severity']:>9s}  {r['category']:>13s}  {r['message'][:35]}")
PYEOF
```

---

## Step 2. Add batch scheduling

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import json
import time
import os
from datetime import datetime
from pathlib import Path

print("""
Batch Scheduling: Run the pipeline at regular intervals.

Three approaches:
  1. cron / pg_cron (external scheduler)
  2. Python loop with sleep (simple, for demos)
  3. Scheduling library (APScheduler, schedule)

For production: use cron or pg_cron.
For this demo: Python loop.
""")

queue_file = "/tmp/alert_queue.jsonl"
results_file = "/tmp/alert_results.jsonl"

def classify_alert(msg):
    cats = {"performance": ["cpu", "slow", "query", "connection"],
            "storage": ["disk", "space", "wal", "full"],
            "replication": ["replication", "lag", "standby"],
            "security": ["login", "ssl", "password"]}
    msg_lower = msg.lower()
    scores = {c: sum(1 for k in kws if k in msg_lower) for c, kws in cats.items()}
    return max(scores, key=scores.get) if max(scores.values()) > 0 else "unknown"

def run_batch():
    """Process pending alerts."""
    if not os.path.exists(queue_file) or os.path.getsize(queue_file) == 0:
        return 0

    with open(queue_file) as f:
        pending = [json.loads(line) for line in f if line.strip()]

    if not pending:
        return 0

    results = []
    for alert in pending:
        results.append({**alert, "category": classify_alert(alert["message"]),
                        "processed_at": datetime.now().isoformat()})

    with open(results_file, "a") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")

    open(queue_file, "w").close()
    return len(results)

# Simulate: alerts arrive while the batch processor runs
print("Simulating batch processing (3 cycles)...")
print("=" * 50)

# Clear previous results
open(results_file, "w").close()

for cycle in range(3):
    # Simulate new alerts arriving
    new_alerts = [
        {"id": cycle * 3 + 1, "message": f"CPU spike detected on server-{cycle+1}", "severity": "high"},
        {"id": cycle * 3 + 2, "message": f"Disk at {80 + cycle * 5}% on /pgdata", "severity": "medium"},
        {"id": cycle * 3 + 3, "message": f"Replication lag {30 * (cycle+1)}s", "severity": "high"},
    ]

    with open(queue_file, "a") as f:
        for a in new_alerts:
            f.write(json.dumps(a) + "\n")

    print(f"\nCycle {cycle + 1}: {len(new_alerts)} new alerts queued")

    # Run batch processing
    processed = run_batch()
    print(f"  Processed: {processed} alerts")
    print(f"  Queue: empty (cleared after processing)")

# Count total results
with open(results_file) as f:
    total = sum(1 for line in f if line.strip())
print(f"\nTotal alerts processed: {total}")

print("""
In production, you would:
  1. Use pg_cron: SELECT cron.schedule('*/5 * * * *', 'SELECT process_alerts()');
  2. Or a crontab: */5 * * * * /usr/bin/python3 /opt/pipeline/batch_processor.py
  3. Or systemd timer for more control
""")
PYEOF
```

---

## Step 3. Batch embedding generation

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import time

print("""
Batch Embedding Generation:
  Instead of generating embeddings one at a time (slow),
  batch them together (fast).

  Single: 100 texts x 50ms each = 5,000ms (5 seconds)
  Batch:  100 texts in one call = 200ms (25x faster)

  This is because GPU/model overhead is per-batch, not per-item.
""")

# Simulate embedding generation
def generate_embeddings_single(texts):
    """Generate embeddings one at a time (slow)."""
    embeddings = []
    for text in texts:
        time.sleep(0.001)  # simulate model inference
        embeddings.append(np.random.randn(384).astype(np.float32))
    return np.array(embeddings)

def generate_embeddings_batch(texts, batch_size=32):
    """Generate embeddings in batches (fast)."""
    embeddings = []
    for i in range(0, len(texts), batch_size):
        batch = texts[i:i + batch_size]
        time.sleep(0.002)  # simulate batch inference (only slightly more than single)
        batch_emb = np.random.randn(len(batch), 384).astype(np.float32)
        embeddings.append(batch_emb)
    return np.vstack(embeddings)
    # np.vstack stacks arrays vertically into one array

# Generate test texts
texts = [f"Alert message number {i} about database issues" for i in range(200)]

# Single
start = time.time()
emb_single = generate_embeddings_single(texts)
single_time = time.time() - start

# Batch
start = time.time()
emb_batch = generate_embeddings_batch(texts, batch_size=32)
batch_time = time.time() - start

print(f"{'Method':20s}  {'Time':>8s}  {'Shape':>15s}")
print("-" * 48)
print(f"{'Single (1 at a time)':20s}  {single_time*1000:>6.0f}ms  {str(emb_single.shape):>15s}")
print(f"{'Batch (32 at a time)':20s}  {batch_time*1000:>6.0f}ms  {str(emb_batch.shape):>15s}")
print(f"\nBatch is {single_time/batch_time:.1f}x faster")

print("""
Production batch embedding pipeline:
  1. Read unembedded documents from database
  2. Batch them (32-64 at a time)
  3. Generate embeddings
  4. Write embeddings back to database
  5. Log how many were processed

  SQL to find unembedded:
    SELECT id, content FROM documents WHERE embedding IS NULL LIMIT 1000;

  After embedding:
    UPDATE documents SET embedding = %s, embedding_updated_at = NOW() WHERE id = %s;
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Batch processing | Process accumulated data at intervals | pg_cron job processing new rows |
| Queue file (JSONL) | Accumulates pending work | Unprocessed rows table |
| Batch clearing | Empty queue after processing | UPDATE SET processed = TRUE |
| Batch scheduling | Run pipeline on a timer | crontab / pg_cron schedule |
| Batch embeddings | Generate many embeddings at once | Bulk INSERT vs single INSERT |
