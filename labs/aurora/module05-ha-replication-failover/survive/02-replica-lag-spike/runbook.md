# SURVIVE 02 - Replica Lag Spike Runbook
## Incident: Aurora Replica Lag Spiking - Users Seeing Stale Data

---

## What Is Being Tested

A write storm on the Aurora writer causes replica lag to spike. Readers serve stale data. You must diagnose the cause, assess impact, and decide on mitigation.

---

## Why This Matters

Replica lag is the most common Aurora operational issue. Batch jobs, ETL loads, and bulk migrations all cause write spikes. If you cannot diagnose and respond to lag quickly, users see stale data and lose trust in your application.

---

## Symptoms

- Users report seeing old data on certain pages
- CloudWatch alarm fires:
```
ALARM: aurora-replica-lag-high
Metric: AuroraReplicaLag > 5000ms
Cluster: devops-lab-cluster
```
- Application "read-your-own-writes" failures (user updates profile, confirmation page shows old data)

---

## Diagnostics

### Step 1 - Confirm the Lag

**In your terminal:**

Connect to the reader endpoint:

```bash
psql -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

**In psql:**

```sql
SELECT
    now() AS current_time,
    pg_last_xact_replay_timestamp() AS last_replayed,
    now() - pg_last_xact_replay_timestamp() AS lag;
```

If lag is above 5 seconds, the incident is confirmed.

### Step 2 - Find the Write Source

**In your terminal:**

Connect to the writer:

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

**In psql:**

```sql
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

Look for long-running INSERT, UPDATE, DELETE, or COPY statements.

### Step 3 - Is Lag Growing or Stable?

Run the lag check twice, 60 seconds apart:

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS lag;
```

- **Growing** - the replica cannot keep up. Escalate immediately.
- **Stable** - the replica is keeping up with current writes but has a backlog. It will recover.
- **Shrinking** - recovery is in progress. Wait.

---

## Resolution

### Option A - Redirect Critical Reads to Writer (Immediate)

For reads that cannot tolerate stale data, temporarily change the application to use the writer endpoint. This adds load to the writer but guarantees fresh data.

### Option B - Stop the Write Source (If Safe)

```sql
SELECT pid, query_start, LEFT(query, 80)
FROM pg_stat_activity
WHERE state = 'active';

-- Kill the heavy write (replace PID)
SELECT pg_terminate_backend(12345);
```

Only do this if you know the query and it is safe to kill.

### Option C - Wait for Recovery

If the write storm is a known batch job, monitor lag as it decreases:

```bash
while true; do
  psql -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -t -c "SELECT now() - pg_last_xact_replay_timestamp();" 2>&1
  sleep 30
done
```

---

## Prevention

- [ ] Schedule ETL and batch jobs during off-peak hours
- [ ] Throttle batch INSERTs with `pg_sleep()` between chunks
- [ ] Set CloudWatch alarm: AuroraReplicaLag > 5000ms for 2 consecutive periods
- [ ] Add "read-your-own-writes" logic for critical application paths
- [ ] Use a dedicated reader for batch/ETL work (custom endpoint, tier 15)

---

## Interview Questions From This Scenario

1. What causes replica lag on Aurora?
2. How do you measure replica lag using SQL vs CloudWatch?
3. What is the "read-your-own-writes" problem and how do you solve it?
4. Why does Aurora have less replica lag than RDS under the same write load?
5. When would you redirect reads to the writer as a mitigation?

---

## Terminology

| Term | Definition |
|------|-----------|
| Replica lag | Time difference between writer committing data and reader seeing it |
| Write storm | Sudden increase in write volume causing replication backlog |
| Stale read | Reading data from a replica that has not yet received recent changes |
| Read-your-own-writes | Pattern where an application writes then immediately reads the same data |
| Cache invalidation | Message from writer to reader saying "data changed, re-read from storage" |

---

## Red Flags

- Lag growing continuously for more than 5 minutes - the replica may be permanently behind
- Lag exceeding 30 minutes - consider adding a larger reader or reducing write volume
- Reader becoming unresponsive - the reader may be out of memory from the replication backlog
- Lag occurring without visible write spikes - check for long-running transactions holding back replication
