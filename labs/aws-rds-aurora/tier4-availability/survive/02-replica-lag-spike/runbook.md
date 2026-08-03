# SURVIVE 02 - Replica Lag Spike Runbook
## Incident: Aurora Replica Lag Spiking - Stale Reads

---

## What You Are Seeing

Users report they see stale or old data on certain pages. A CloudWatch alarm fired:

```
ALARM: aurora-replica-lag-high
Metric: AuroraReplicaLag > 5000ms
Cluster: my-aurora-cluster
```

---

## Step 1 - Confirm the Lag

Connect to the reader endpoint and check lag directly:

```bash
psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

```sql
SELECT
    now() AS current_time,
    pg_last_xact_replay_timestamp() AS last_replayed,
    now() - pg_last_xact_replay_timestamp() AS lag;
```

Expected output during the incident (yours will differ):
```
        current_time         |       last_replayed        |    lag
-----------------------------+----------------------------+------------
 2024-01-15 15:20:00.000000 | 2024-01-15 15:18:45.000000 | 00:01:15
```

75 seconds of lag. Reads from the reader are showing data that is 75 seconds old.

Check CloudWatch for context:

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

---

## Step 2 - Find What Is Causing the Writes

Check write I/O on the cluster to identify a write storm:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name WriteIOPS \
  --dimensions Name=DBClusterIdentifier,Value=my-aurora-cluster \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Sum \
  --region us-east-1
```

If WriteIOPS is very high (hundreds or thousands above baseline), something is generating heavy write load.

Connect to the writer and look for the culprit query:

```bash
psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

```sql
-- Find long-running queries
SELECT
    pid,
    now() - query_start AS duration,
    state,
    LEFT(query, 100) AS query_snippet
FROM pg_stat_activity
WHERE state != 'idle'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration DESC;
```

Expected output (yours will differ):
```
  pid  | duration |  state  |        query_snippet
-------+----------+---------+----------------------------
 12345 | 00:02:15 | active  | INSERT INTO survive_lag_test (payload, batch_id) SELECT md5...
```

A long-running bulk INSERT is the cause.

---

## Step 3 - Assess Impact on Users

Is the lag increasing or stable?

Run the lag check twice, 60 seconds apart:

```sql
-- First check
SELECT now() - pg_last_xact_replay_timestamp() AS lag;
-- Note the value

-- Wait 60 seconds, then run again
SELECT now() - pg_last_xact_replay_timestamp() AS lag;
```

- If lag is GROWING - the replica cannot keep up. Escalate immediately.
- If lag is STABLE (not growing) - the replica is keeping up but has a backlog. It will recover when writes slow down.
- If lag is SHRINKING - recovery is in progress. Wait it out.

---

## Step 4 - Immediate Mitigation Options

### Option A - Redirect Reads to the Writer Temporarily (Most Impactful)

For critical reads that cannot tolerate stale data, change the application connection string temporarily from the reader endpoint to the writer endpoint. This adds load to the writer but guarantees fresh reads.

This is a temporary measure. Plan to switch back when lag recovers.

### Option B - Inform Users and Wait

If the write storm is a known batch job that will finish soon, you may be able to inform users that some data is temporarily delayed and wait for the job to complete.

### Option C - Stop the Causing Process

If the heavy write is an ETL job or bulk operation that can be paused:

```sql
-- Find the PID of the heavy INSERT
SELECT pid, query_start, LEFT(query, 80) FROM pg_stat_activity WHERE state = 'active';

-- Kill it (replace 12345 with the actual PID)
SELECT pg_terminate_backend(12345);
```

Only do this if you know what the query is and it is safe to kill.

---

## Step 5 - Monitor Recovery

Watch the lag decrease:

```bash
# Run this every 30 seconds to watch recovery
while true; do
  psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -t -c "SELECT now() - pg_last_xact_replay_timestamp();" 2>&1
  sleep 30
done
```

Expected recovery output:
```
00:01:15
00:00:58
00:00:40
00:00:22
00:00:08
00:00:01
```

Once lag returns to under 1 second, reads are effectively real-time again.

---

## Step 6 - Post-Incident Review

Write a brief summary:

```
Incident: Replica Lag Spike
Date: [DATE]
Duration of elevated lag: [N minutes]
Peak lag: [N seconds]
Cause: [Bulk INSERT / ETL job / Unknown]
Impact: [Stale reads for users on these pages: ...]
Resolution: [Waited for job to complete / Killed the query / Redirected reads]
Action items:
  - [ ] Schedule large batch jobs during off-hours
  - [ ] Add read_after_write routing for critical paths in the application
  - [ ] Set a CloudWatch alarm for AuroraReplicaLag > 5000ms
  - [ ] Consider running batch jobs against a dedicated reader, not the writer
```

---

## Prevention Checklist

- [ ] Schedule ETL and batch jobs during off-peak hours
- [ ] Use `pg_sleep()` between large batch INSERT chunks to throttle write rate
- [ ] Set CloudWatch alarm: AuroraReplicaLag > 5000ms for 2 consecutive periods
- [ ] Add application logic for "read-your-own-writes" on critical paths
- [ ] Consider a dedicated reader for batch/ETL work so they do not share the OLTP reader pool
