# USE 02 - Replica Lag Diagnosis and Response
## Apply What You Learned | Module 05

---

## Instructions

Complete each exercise. Work through the scenario, write your answer, then reveal the solution.

---

## Exercise 1 - Measure Baseline Lag

Connect to your reader endpoint and run:

```sql
SELECT
    now() AS current_time,
    pg_last_xact_replay_timestamp() AS last_replayed,
    now() - pg_last_xact_replay_timestamp() AS lag,
    pg_is_in_recovery() AS is_replica;
```

Write down the lag value. This is your baseline.

**Question:** What is healthy baseline lag for Aurora replicas? What about RDS read replicas?

<details>
<summary>Click to reveal solution</summary>

Aurora replicas: healthy baseline is under 100ms, often under 20ms. This is because Aurora replicas share storage with the writer - they do not need to receive and apply WAL.

RDS read replicas: healthy baseline is 100-500ms at low load. Under heavy write load, lag can spike to seconds. This is because RDS replicas must receive WAL over the network and apply it to their own EBS volumes.

</details>

---

## Exercise 2 - Generate Write Load and Watch Lag

On the writer, run a bulk insert:

```sql
CREATE TABLE IF NOT EXISTS lag_exercise (
    id SERIAL PRIMARY KEY,
    payload TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO lag_exercise (payload)
SELECT md5(random()::text)
FROM generate_series(1, 500000);
```

While the insert runs, check lag on the reader every 10 seconds:

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS lag;
```

**Question:** Does lag increase during the bulk insert? By how much?

<details>
<summary>Click to reveal solution</summary>

Lag may increase slightly - typically to 100-500ms on Aurora. This is much less than RDS read replicas would experience under the same load.

The reason Aurora handles this well: replicas do not receive WAL and apply it. They share the same storage. The writer sends cache invalidation messages, and the reader re-reads from shared storage. The only lag is the time for the storage to become visible to the reader.

</details>

---

## Exercise 3 - On-Call Scenario

You receive this alert at 2 AM:

```
ALARM: aurora-replica-lag-high
Metric: AuroraReplicaLag > 5000ms
Cluster: devops-lab-cluster
Time: 2026-06-09 02:15:00 UTC
```

You check CloudWatch and see WriteIOPS spiked from 50 to 8000 at 02:10 UTC.

**Question 1:** What is the most likely cause?

**Question 2:** The lag is steady at 45 seconds (not growing). What does this tell you?

**Question 3:** List three actions you could take to recover.

<details>
<summary>Click to reveal solution</summary>

**Q1:** A bulk write operation - likely an ETL job, batch insert, or migration script started at 02:10 UTC. The massive write spike is overwhelming the replica's ability to keep up.

**Q2:** Steady lag (not growing) means the replica is keeping up with CURRENT writes but has a backlog from the initial spike. The write storm has either ended or stabilized. The replica is slowly catching up. This is a good sign - the situation will resolve itself.

**Q3:** Three actions:
1. **Identify and throttle the write source:** Connect to the writer and run `SELECT pid, query_start, LEFT(query, 80) FROM pg_stat_activity WHERE state = 'active';` to find the heavy write query. If safe, kill it with `SELECT pg_terminate_backend(PID);`
2. **Redirect critical reads to the writer temporarily:** For any application path that cannot tolerate stale data, change the connection string to the writer endpoint until lag recovers
3. **Wait and monitor:** If the write storm is a known batch job that will finish soon, simply monitor the lag as it decreases. Set a follow-up alarm check in 30 minutes

</details>

---

## Exercise 4 - CloudWatch Alarm Design

Design a CloudWatch alarm for replica lag that avoids false positives.

**Question:** Why should you set `--evaluation-periods 2` instead of 1? What problem does that prevent?

<details>
<summary>Click to reveal solution</summary>

Setting `--evaluation-periods 2` requires the metric to breach the threshold for 2 consecutive periods before the alarm fires. This prevents false alarms from momentary lag spikes.

A single lag spike lasting 30 seconds (one evaluation period) might be caused by a large transaction committing or a brief network hiccup. These resolve on their own. Waking someone at 2 AM for a self-resolving spike is a waste.

Two consecutive periods of high lag (2+ minutes at default 60-second periods) indicates a sustained problem that needs human attention.

</details>

---

## Exercise 5 - Read-Your-Own-Writes Problem

Your application inserts a user's profile update, then immediately reads it back to show a confirmation page.

```
App writes: INSERT INTO users (name) VALUES ('Alice') -- goes to writer
App reads:  SELECT * FROM users WHERE name = 'Alice'  -- goes to reader
```

The user sometimes sees the OLD profile data on the confirmation page.

**Question:** What is happening? List three ways to fix it.

<details>
<summary>Click to reveal solution</summary>

The application wrote to the writer but read from the reader (via the reader endpoint). Due to replica lag (even just 20ms), the reader has not yet received the change. The user sees stale data.

Three fixes:
1. **Route post-write reads to the writer endpoint:** After any write operation, the application reads from the cluster (writer) endpoint for that user's session. This guarantees fresh data at the cost of additional load on the writer.

2. **Use Aurora session consistency:** On the reader connection, set `SET aurora_replica_read_consistency = 'SESSION';`. This tells the reader to wait until it has replayed up to the session's last write LSN before serving reads. Adds small latency but guarantees consistency.

3. **Application-level session flag:** After a write, set a flag in the user's session (e.g., `read_from_writer=true` for 5 seconds). The application checks this flag and routes reads to the writer for that brief window. After the window expires, reads return to the reader endpoint.

</details>
