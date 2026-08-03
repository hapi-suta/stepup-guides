# BUILD 02 - Failover Testing: Trigger, Measure, Verify
## Estimated Time: 40 minutes

---

## What You Will Do

1. Record pre-failover state (writer, IP, AZ)
2. Set up a connection monitor to measure downtime
3. Trigger an Aurora failover via CLI
4. Observe the failover in real-time
5. Verify the new writer and measure actual RTO
6. Check failover events in the Events log

> **Cost warning:** This lab uses the cluster from BUILD 01. No additional resources are created.

---

## Before You Start

You need:
- The Aurora cluster from BUILD 01 (`devops-lab-cluster`) with writer + reader in "available" status
- Two terminal windows open
- AWS CLI v2 configured
- psql installed

---

## Step 1 - Record Pre-Failover State

**In your terminal:**

Check which instance is the current writer:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter,Tier:PromotionTier}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------------------------------
|             DescribeDBClusters                     |
+---------------------+--------+--------------------+
| Instance            | Tier   | Writer             |
+---------------------+--------+--------------------+
| devops-lab-writer   | 1      | True               |
| devops-lab-reader-1 | 0      | False              |
+---------------------+--------+--------------------+
```

Record the current writer IP:

```bash
dig +short devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

`dig +short` - returns just the IP address without extra DNS information.

Expected output (yours will differ):
```
10.0.1.23
```

Write down this IP. After failover, it will change.

---

## Step 2 - Record Pre-Failover Database State

**In your terminal:**

Connect to the writer and create a test table:

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

```sql
CREATE TABLE IF NOT EXISTS failover_test (
    id SERIAL PRIMARY KEY,
    message TEXT,
    written_by TEXT DEFAULT inet_server_addr()::text,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO failover_test (message) VALUES ('pre-failover write');

SELECT id, message, written_by, created_at FROM failover_test;
```

Expected output (yours will differ):
```
 id |      message       | written_by |          created_at
----+--------------------+------------+-------------------------------
  1 | pre-failover write | 10.0.1.23  | 2026-06-09 14:00:00.123456+00
(1 row)
```

Note the `written_by` IP. After failover, new writes will show a different IP.

Exit psql:

```sql
\q
```

---

## Step 3 - Set Up the Connection Monitor

**In Terminal 1:**

This script connects to the writer endpoint every second and shows whether the connection succeeds or fails. It measures the total failover downtime.

```bash
ENDPOINT="devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com"

echo "Starting connection monitor. Press Ctrl+C to stop."
echo "Time       | Status | Server IP"
echo "-----------|--------|----------"

FAIL_START=""
FAIL_END=""

while true; do
  RESULT=$(psql -h "$ENDPOINT" -U postgres -d postgres \
    -t -c "SELECT inet_server_addr()::text;" \
    --connect-timeout=3 2>&1)

  if echo "$RESULT" | grep -qE '^[0-9]+\.[0-9]+'; then
    IP=$(echo "$RESULT" | tr -d ' ')
    echo "$(date -u +%H:%M:%S) | OK     | $IP"
    if [ -n "$FAIL_START" ] && [ -z "$FAIL_END" ]; then
      FAIL_END=$(date -u +%s)
      DOWNTIME=$((FAIL_END - FAIL_START))
      echo ">>> FAILOVER COMPLETE. Downtime: ${DOWNTIME} seconds <<<"
    fi
  else
    if [ -z "$FAIL_START" ]; then
      FAIL_START=$(date -u +%s)
      echo "$(date -u +%H:%M:%S) | FAIL   | Connection error - failover started"
    else
      echo "$(date -u +%H:%M:%S) | FAIL   | Still recovering..."
    fi
  fi

  sleep 1
done
```

Replace `xxxx` with your actual cluster ID. Leave this running in Terminal 1.

Expected output before failover:
```
Time       | Status | Server IP
-----------|--------|----------
14:05:01   | OK     | 10.0.1.23
14:05:02   | OK     | 10.0.1.23
14:05:03   | OK     | 10.0.1.23
```

---

## Step 4 - Trigger the Failover

**In Terminal 2:**

Note the exact time:

```bash
echo "FAILOVER TRIGGERED AT: $(date -u)"
```

Trigger the failover:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --region us-east-1
```

`--db-cluster-identifier` - the cluster to fail over. Aurora will promote the highest-priority reader (tier 0).

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-cluster",
        "Status": "failing-over",
        ...
    }
}
```

---

## Step 5 - Observe the Failover in Real-Time

**In Terminal 1:**

Watch the connection monitor. You will see something like:

```
14:05:10   | OK     | 10.0.1.23
14:05:11   | OK     | 10.0.1.23
14:05:12   | FAIL   | Connection error - failover started
14:05:13   | FAIL   | Still recovering...
14:05:14   | FAIL   | Still recovering...
...
14:05:32   | OK     | 10.0.2.45
>>> FAILOVER COMPLETE. Downtime: 20 seconds <<<
14:05:33   | OK     | 10.0.2.45
```

Key observations:
1. The server IP changed (10.0.1.23 to 10.0.2.45) - you are now on a different instance
2. The downtime was approximately 20 seconds
3. The cluster endpoint hostname did not change - DNS was updated behind the scenes

Typical Aurora failover time: 20-35 seconds.

---

## Step 6 - Verify the New Writer

**In Terminal 2:**

Check which instance is the writer now:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------------------------------
|             DescribeDBClusters                     |
+---------------------+-----------------------------+
| Instance            | Writer                      |
+---------------------+-----------------------------+
| devops-lab-writer   | False                       |
| devops-lab-reader-1 | True                        |
+---------------------+-----------------------------+
```

`devops-lab-reader-1` is now the writer (`True`). The original writer is now a reader.

---

## Step 7 - Verify DNS Updated

**In Terminal 2:**

```bash
dig +short devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

Expected output (yours will differ):
```
10.0.2.45
```

Compare this to the IP you recorded in Step 1. It should be different - the DNS now points to the new writer.

---

## Step 8 - Test Read and Write on the New Writer

**In Terminal 2:**

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

```sql
INSERT INTO failover_test (message) VALUES ('post-failover write');

SELECT id, message, written_by, created_at FROM failover_test ORDER BY id;
```

Expected output (yours will differ):
```
 id |       message        | written_by |          created_at
----+----------------------+------------+-------------------------------
  1 | pre-failover write   | 10.0.1.23  | 2026-06-09 14:00:00.123456+00
  2 | post-failover write  | 10.0.2.45  | 2026-06-09 14:05:35.654321+00
(2 rows)
```

Notice:
- Row 1 was written by the old writer (10.0.1.23)
- Row 2 was written by the new writer (10.0.2.45)
- No data was lost during failover (row 1 is still there)

Exit psql:

```sql
\q
```

---

## Step 9 - Check Failover Events

**In Terminal 2:**

```bash
aws rds describe-events \
  --source-identifier devops-lab-cluster \
  --source-type db-cluster \
  --duration 30 \
  --region us-east-1
```

`--source-type db-cluster` - show events for the cluster (not individual instances).
`--duration 30` - events from the past 30 minutes.

Expected output (yours will differ):
```json
{
    "Events": [
        {
            "Message": "A failover for the DB cluster has started.",
            "EventCategories": ["failover"],
            "Date": "2026-06-09T14:05:12.000Z"
        },
        {
            "Message": "DB cluster failover completed. devops-lab-reader-1 is now the writer instance.",
            "EventCategories": ["failover"],
            "Date": "2026-06-09T14:05:32.000Z"
        }
    ]
}
```

Calculate the failover duration from the event timestamps. In this example: 14:05:32 - 14:05:12 = 20 seconds.

---

## Step 10 - Failover Back to the Original Writer (Optional)

If you want to restore the original writer:

**In Terminal 2:**

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --target-db-instance-identifier devops-lab-writer \
  --region us-east-1
```

`--target-db-instance-identifier` - force failover to a specific instance. Aurora promotes this instance to writer.

Wait 20-35 seconds and verify:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

---

## Key Takeaways

1. Aurora failover typically completes in 20-35 seconds
2. The cluster endpoint DNS updates within 5 seconds of failover
3. No data is lost during failover (RPO = 0)
4. The old writer becomes a reader - no instances are deleted
5. You can force failover to a specific instance with `--target-db-instance-identifier`
6. Always check Events after failover to record the exact timestamps
7. Applications must have connection retry logic - failover causes brief connection drops

---

## Clean Up

Keep the cluster running for BUILD 03. Press Ctrl+C to stop the connection monitor in Terminal 1.
