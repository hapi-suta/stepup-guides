# USE 02 - Replica Management Under Load
## Apply What You Learned | Tier 4

---

## What You Will Practice

- Diagnosing replica lag using SQL and CloudWatch
- Understanding what causes replica lag to increase
- Responding to lag alerts
- Deciding when to scale or add replicas

---

## Setup

You need your Aurora cluster from the BUILD labs with at least one reader running.

Connect to your writer in one terminal:

```bash
psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

Connect to the reader endpoint in a second terminal:

```bash
psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

---

## Exercise 1 - Measure Baseline Lag

On the reader, run:

```sql
SELECT
    now() AS current_time,
    pg_last_xact_replay_timestamp() AS last_replayed,
    now() - pg_last_xact_replay_timestamp() AS lag,
    pg_is_in_recovery() AS is_replica;
```

Write down the lag value. This is your baseline.

**Question 1:** What is the lag at idle? Is it under 100 milliseconds?

---

## Exercise 2 - Generate Write Load and Watch Lag

On the writer terminal, create a table and run a bulk insert loop:

```sql
CREATE TABLE lag_test (
    id SERIAL PRIMARY KEY,
    payload TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

Now run this loop in the writer terminal (it runs for 60 seconds):

```bash
psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres << 'EOF'
DO $$
DECLARE
    i INT := 0;
BEGIN
    WHILE i < 600000 LOOP
        INSERT INTO lag_test (payload)
        SELECT md5(random()::text)
        FROM generate_series(1, 100);
        COMMIT;
        i := i + 100;
        PERFORM pg_sleep(0.1);
    END LOOP;
END$$;
EOF
```

While that runs, check the lag on the reader every 10 seconds:

```sql
-- Run this repeatedly on the reader terminal
SELECT
    now() - pg_last_xact_replay_timestamp() AS lag,
    pg_last_xact_replay_timestamp() AS last_replayed;
```

**Question 2:** Does the lag increase during the write storm? By how much?

**Question 3:** For Aurora replicas, why is the lag much smaller than you might see on RDS read replicas under the same load?

---

## Exercise 3 - Simulate an Application Reading Stale Data

This exercise shows the practical impact of replica lag.

On the writer, insert a specific row:

```sql
INSERT INTO lag_test (payload) VALUES ('IMPORTANT_UPDATE_' || now())
RETURNING id, created_at;
```

Note the `id` that was returned.

Immediately on the reader, check if you can see it:

```sql
-- Replace 9999 with the actual ID returned above
SELECT * FROM lag_test WHERE id = 9999;
```

**Question 4:** Did the row appear immediately on the reader? Or did you need to wait a moment?

**Question 5:** If your application inserts a record and then immediately reads it from the reader endpoint, what problem could occur? How would you fix it?

---

## Exercise 4 - Check Replica Lag in CloudWatch

Get the lag metric for the past 30 minutes:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBClusterIdentifier,Value=my-aurora-cluster \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region us-east-1
```

**Question 6:** What was the maximum lag during your write storm? At what point did it return to baseline?

---

## Exercise 5 - Set a CloudWatch Alarm for Replica Lag

Create an alarm that alerts you when replica lag exceeds 5 seconds:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name aurora-replica-lag-high \
  --alarm-description "Aurora replica lag exceeded 5 seconds" \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBClusterIdentifier,Value=my-aurora-cluster \
  --statistic Maximum \
  --period 60 \
  --threshold 5000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --region us-east-1
```

`--threshold 5000` - 5000 milliseconds = 5 seconds. `AuroraReplicaLag` is in milliseconds.
`--evaluation-periods 2` - must exceed threshold for 2 consecutive periods before alarming.

**Question 7:** Why use `--evaluation-periods 2` instead of 1? What problem does that prevent?

---

## Exercise 6 - Add a Second Reader to Distribute Read Load

If read traffic is high, add a second reader:

```bash
aws rds create-db-instance \
  --db-instance-identifier my-aurora-reader-3 \
  --db-cluster-identifier my-aurora-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --availability-zone us-east-1c \
  --promotion-tier 2 \
  --region us-east-1
```

**Question 8:** After adding a third reader, what changes about how the reader endpoint distributes connections? Do you need to change your application code?

---

## Exercise 7 - Simulated On-Call Scenario

You receive this alert at 2 AM:

```
ALERT: AuroraReplicaLag > 30000ms on my-aurora-cluster (reader: my-aurora-reader-1)
Time: 2024-01-15 02:15:00 UTC
```

You log in and check:

```sql
-- On the reader
SELECT now() - pg_last_xact_replay_timestamp() AS lag;
```

Result: 45 seconds of lag.

```bash
# Check CloudWatch for write activity
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name WriteIOPS \
  --dimensions Name=DBClusterIdentifier,Value=my-aurora-cluster \
  --start-time 2024-01-15T02:00:00Z \
  --end-time 2024-01-15T02:30:00Z \
  --period 60 \
  --statistics Sum \
  --region us-east-1
```

Result: WriteIOPS spiked from 50 to 8000 at 02:10 UTC.

**Question 9:** What is the most likely cause of the lag spike?

**Question 10:** The lag is not growing - it is steady at 45 seconds. What does steady lag (not increasing) tell you about the current state?

**Question 11:** What are three things you could do to recover if the lag were increasing continuously?

---

## Answer Guide

**Q1:** Baseline lag on Aurora should be under 100ms, often 10-50ms.

**Q2:** Lag may spike to 100-500ms under heavy write load. Aurora is much better than RDS at this because replicas share storage and do not need to replay WAL.

**Q3:** Aurora replicas share the same storage layer. They do not receive WAL streams and replay them. Instead they just learn the latest LSN and read from shared storage. This is fundamentally faster.

**Q4:** For very small lag (under 100ms), the row likely appears immediately. Under heavy load, you may need to wait a fraction of a second.

**Q5:** "Read-your-own-writes" problem. Fix options: (a) read critical data from the writer endpoint after a write, (b) use application-level sessions that track which endpoint to use, (c) add `SET SESSION CHARACTERISTICS AS TRANSACTION READ WRITE` for those queries.

**Q6:** Varies by your test. Baseline should return within 30 seconds after the write storm ends.

**Q7:** Prevents false alarms from a single momentary lag spike. Requiring 2 consecutive periods means the lag must be sustained before you wake someone up at 2 AM.

**Q8:** The reader endpoint automatically includes the new reader in DNS rotation. No application code changes needed. New connections are distributed across all three readers.

**Q9:** A bulk write job, ETL load, or batch process started at 02:10 UTC. The high WriteIOPS caused a temporary lag spike.

**Q10:** Steady lag means the replica is keeping up with current writes but has not yet caught up to the backlog. The write storm is over or slowed down. The replica is recovering.

**Q11:**
- (a) Temporarily stop non-critical reads from hitting that replica (redirect them to the writer)
- (b) If the write storm is from a batch job, throttle or pause the batch job
- (c) If the reader is undersized, add a larger reader and remove the lagging one
