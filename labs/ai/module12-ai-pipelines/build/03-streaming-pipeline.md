# Build 03: Streaming Pipeline

A streaming pipeline processes events as they arrive - no waiting for a batch. This is for real-time scenarios: classify an alert the moment it fires, detect anomalies as metrics flow in.

---

## Step 1. Event-driven processing

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import queue
import threading
import time
import json
from datetime import datetime

print("""
Streaming Pipeline: Process each event immediately.

Pattern:
  Producer -> Queue -> Consumer -> Action

DBA analogy:
  - Producer = pg_notify sending events
  - Queue = the notification channel
  - Consumer = LISTEN handler processing events
  - Action = trigger an alert, update a dashboard
""")

# Simple in-memory queue (production would use Redis, Kafka, or pg_notify)
event_queue = queue.Queue()
# queue.Queue is thread-safe: multiple producers and consumers can use it safely

results = []
running = True

def classify_alert(message):
    """Quick classification."""
    msg = message.lower()
    if any(w in msg for w in ["cpu", "slow", "query", "connection"]):
        return "performance"
    elif any(w in msg for w in ["disk", "space", "wal"]):
        return "storage"
    elif any(w in msg for w in ["replication", "lag", "standby"]):
        return "replication"
    elif any(w in msg for w in ["login", "ssl", "password"]):
        return "security"
    return "unknown"

# Consumer: processes events from the queue
def consumer():
    """Process events as they arrive."""
    while running:
        try:
            event = event_queue.get(timeout=0.5)
            # .get(timeout=0.5) waits up to 0.5s for an event
            # If no event arrives, it raises queue.Empty

            # Process the event
            start = time.time()
            category = classify_alert(event["message"])
            latency = (time.time() - start) * 1000

            result = {
                **event,
                "category": category,
                "processed_at": datetime.now().isoformat(),
                "latency_ms": latency,
            }
            results.append(result)
            print(f"  Processed: [{category:>13s}] {event['message'][:40]}  ({latency:.1f}ms)")

            event_queue.task_done()
            # .task_done() signals that the event has been fully processed

        except queue.Empty:
            continue  # no events, keep waiting

# Start consumer thread
# A thread runs code in the background while other code continues.
# threading.Thread(target=consumer) creates a thread that will run the consumer function.
# daemon=True means: when the main program exits, this thread stops too.
# DBA analogy: like a background worker process in PostgreSQL (autovacuum, WAL writer).
# target=consumer passes the function itself (not calling it) - like a callback.
consumer_thread = threading.Thread(target=consumer, daemon=True)
consumer_thread.start()

# Producer: simulate alerts arriving over time
alerts = [
    {"message": "CPU usage exceeded 95% on pg-primary", "severity": "critical"},
    {"message": "Replication lag reached 120 seconds", "severity": "high"},
    {"message": "Disk space at 92% on /pgdata", "severity": "medium"},
    {"message": "Failed login attempt from 10.0.0.99", "severity": "high"},
    {"message": "Slow query: 45s sequential scan on orders", "severity": "medium"},
    {"message": "Connection pool exhausted - 100/100", "severity": "critical"},
]

print("Streaming Pipeline - Processing events in real time:")
print("=" * 60)

for i, alert in enumerate(alerts):
    alert["id"] = i + 1
    alert["timestamp"] = datetime.now().isoformat()
    event_queue.put(alert)
    # .put() adds an event to the queue
    time.sleep(0.1)  # simulate events arriving over time

# Wait for all events to be processed
event_queue.join()
# .join() blocks until all items in the queue have been processed

running = False
consumer_thread.join()

print(f"\nProcessed {len(results)} events in real time")
avg_latency = sum(r["latency_ms"] for r in results) / len(results)
print(f"Average processing latency: {avg_latency:.2f}ms")
PYEOF
```

---

## Step 2. PostgreSQL LISTEN/NOTIFY pipeline

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import psycopg2
import os
import json
import time
import select
from datetime import datetime

print("""
PostgreSQL LISTEN/NOTIFY: Built-in event streaming.

How it works:
  1. Application sends: NOTIFY alert_channel, 'payload'
  2. Listener receives the event immediately
  3. No external message queue needed

This is the simplest streaming pipeline for PostgreSQL.
""")

conn = psycopg2.connect(host="localhost", port=5432, user=os.environ.get("USER"), dbname="postgres")
conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
# AUTOCOMMIT is required for LISTEN/NOTIFY to work properly
cur = conn.cursor()

# Create a notification trigger (would be on your alerts table)
cur.execute("""
    CREATE OR REPLACE FUNCTION notify_new_alert()
    RETURNS trigger AS $$
    BEGIN
        PERFORM pg_notify('alert_channel', row_to_json(NEW)::text);
        -- pg_notify sends a notification on the named channel
        -- row_to_json converts the new row to JSON
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
""")

# Create a test table
cur.execute("DROP TABLE IF EXISTS live_alerts")
cur.execute("""
    CREATE TABLE live_alerts (
        id SERIAL PRIMARY KEY,
        message TEXT,
        severity TEXT,
        created_at TIMESTAMP DEFAULT NOW()
    )
""")

cur.execute("""
    DROP TRIGGER IF EXISTS trg_new_alert ON live_alerts;
    CREATE TRIGGER trg_new_alert
    AFTER INSERT ON live_alerts
    FOR EACH ROW EXECUTE FUNCTION notify_new_alert();
""")

# Start listening
cur.execute("LISTEN alert_channel")
print("Listening on 'alert_channel'...")

# Simulate: insert alerts (producer)
test_alerts = [
    ("CPU at 97% on pg-primary", "critical"),
    ("Replication lag 90 seconds", "high"),
    ("Disk at 95% on /pgdata", "critical"),
]

# Insert alerts (this triggers notifications)
for msg, sev in test_alerts:
    cur.execute("INSERT INTO live_alerts (message, severity) VALUES (%s, %s)", (msg, sev))

# Listen for notifications
print("\nReceived notifications:")
print("-" * 60)

received = 0
max_wait = 2  # seconds to wait for notifications
start = time.time()

while time.time() - start < max_wait and received < len(test_alerts):
    # select.select checks if there's data to read on the connection
    if select.select([conn], [], [], 0.5) != ([], [], []):
        # select returns non-empty lists if there's data
        conn.poll()
        # .poll() fetches pending notifications

        while conn.notifies:
            notify = conn.notifies.pop(0)
            # .notifies is a list of pending notifications
            # .pop(0) removes and returns the first one

            payload = json.loads(notify.payload)
            # Parse the JSON payload

            # Classify the alert
            msg = payload["message"].lower()
            if "cpu" in msg or "slow" in msg:
                category = "performance"
            elif "disk" in msg or "space" in msg:
                category = "storage"
            elif "replication" in msg or "lag" in msg:
                category = "replication"
            else:
                category = "unknown"

            print(f"  [{payload['severity']:>8s}] [{category:>13s}] {payload['message']}")
            received += 1

print(f"\nReceived and classified {received} alerts via LISTEN/NOTIFY")
print("No external message queue needed - just PostgreSQL!")

# Cleanup
cur.execute("UNLISTEN alert_channel")
cur.close()
conn.close()
PYEOF
```

Expected output (yours will differ):

```
Listening on 'alert_channel'...

Received notifications:
------------------------------------------------------------
  [critical] [  performance] CPU at 97% on pg-primary
  [    high] [  replication] Replication lag 90 seconds
  [critical] [      storage] Disk at 95% on /pgdata

Received and classified 3 alerts via LISTEN/NOTIFY
```

---

## Step 3. Batch vs Streaming - when to use each

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Batch vs Streaming Pipeline - Decision Guide:

USE BATCH WHEN:
  - Latency tolerance > 1 minute (hourly reports, daily retraining)
  - Processing is expensive (model training, bulk embeddings)
  - Data comes in chunks (log files, CSV imports)
  - Efficiency matters more than speed (batch is cheaper per item)
  - Example: regenerate embeddings for 10K documents nightly

USE STREAMING WHEN:
  - Latency tolerance < 10 seconds (real-time alerts, live monitoring)
  - Each event needs immediate action (page the on-call, trigger failover)
  - Events arrive continuously (monitoring metrics, user requests)
  - Example: classify each alert as it fires

USE HYBRID WHEN:
  - Streaming for inference (classify alerts in real time)
  - Batch for training (retrain the model weekly)
  - This is the most common production pattern

IMPLEMENTATION OPTIONS:

Simple:
  Batch:     cron + Python script
  Streaming: pg_notify + Python listener

Medium:
  Batch:     Luigi / Prefect
  Streaming: Redis pub/sub + Python consumer

Complex:
  Batch:     Apache Airflow
  Streaming: Apache Kafka + consumer group

For most DBA pipelines, the SIMPLE option is sufficient.
pg_notify for real-time, cron for batch processing.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Event queue | Holds events until processed | pg_notify channel |
| Consumer thread | Processes events in background | LISTEN handler |
| LISTEN/NOTIFY | PostgreSQL built-in event streaming | Real-time trigger-based processing |
| Streaming pipeline | Process each event immediately | Real-time replication events |
| Batch vs streaming | Choose based on latency needs | OLTP (real-time) vs OLAP (batch) |
