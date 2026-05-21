# Exercise 04 - Measure Replication Lag Under Load (CentOS Stream 9)

**Time estimate:** 20-30 minutes
**Prerequisites:** Exercise 03 complete - NODE2 is primary, NODE1 is standby, both streaming on timeline 2

---

## Objective

Generate write load on the primary and observe replication lag using three different measurement methods. Understand when each method is appropriate and what it tells you.

---

## Step 1 - Set Up pgbench on the Primary

On **NODE2** (primary), switch to the postgres user:

```bash
sudo -iu postgres
```

Initialize pgbench tables in labdb:

```bash
pgbench -i -s 10 -h [NODE2_IP] -U postgres labdb
```

**Expected output (yours will differ):**
```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done
vacuuming...
creating primary keys...
done in X.XX s
```

This creates the `pgbench_accounts`, `pgbench_branches`, `pgbench_tellers`, and `pgbench_history` tables with 1 million rows.

> **Concept:** `pgbench` is PostgreSQL's built-in benchmarking tool. The `-s 10` flag sets the scale factor to 10 (1 million rows in pgbench_accounts). This gives us enough data to generate meaningful WAL volume and observable replication lag.

---

## Step 2 - Verify pgbench Tables Replicated

On **NODE1** (standby), switch to the postgres user:

```bash
sudo -iu postgres
```

```sql
\c labdb

SELECT count(*) FROM pgbench_accounts;
```

**Expected:**
```
  count
---------
 1000000
```

---

## Method 1 - Measure Lag in Bytes (pg_wal_lsn_diff)

### Start a write load

On **NODE2** (primary), as the postgres user, open a second SSH session and run:

```bash
sudo -iu postgres
```

```bash
pgbench -c 4 -j 2 -T 120 -h [NODE2_IP] -U postgres labdb
```

This runs 4 concurrent clients for 120 seconds.

### While pgbench runs, measure byte lag

On **NODE2** (primary), in another connection as the postgres user:

```sql
SELECT
    client_addr,
    pg_current_wal_lsn() AS current_lsn,
    replay_lsn,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_lag_pretty
FROM pg_stat_replication;
```

Run this query several times during the load to see the lag fluctuate.

> **Concept:** Byte lag tells you how far behind the standby is in terms of WAL volume. This is the most precise metric because it measures the actual data gap. However, raw bytes are hard to interpret without context - 1 MB of lag during a bulk load is very different from 1 MB of lag during normal OLTP traffic.

### Break down each stage of lag

```sql
SELECT
    client_addr,
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS send_lag_bytes,
    pg_wal_lsn_diff(sent_lsn, write_lsn) AS write_lag_bytes,
    pg_wal_lsn_diff(write_lsn, flush_lsn) AS flush_lag_bytes,
    pg_wal_lsn_diff(flush_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
```

> **Concept:** Breaking lag into stages helps you diagnose where the bottleneck is. If `send_lag_bytes` is high, the primary cannot send WAL fast enough (network or primary I/O). If `write_lag_bytes` is high, the standby cannot write to disk fast enough (standby disk I/O). If `replay_lag_bytes` is high, the standby cannot apply WAL fast enough (standby CPU or I/O). In most real-world scenarios, replay lag dominates because applying WAL is the most CPU-intensive step.

---

## Method 2 - Measure Lag in Time

### On NODE2 (primary) - PG 10+ built-in time lag

As the postgres user:

```sql
SELECT
    client_addr,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication;
```

### On NODE1 (standby) - replay timestamp method

As the postgres user:

```sql
SELECT
    now() AS standby_time,
    pg_last_xact_replay_timestamp() AS last_replay,
    now() - pg_last_xact_replay_timestamp() AS replay_lag;
```

> **Concept:** Time-based lag is what matters most to applications. A user running a query on the standby wants to know: "How old is this data?" The `write_lag`, `flush_lag`, and `replay_lag` columns in `pg_stat_replication` (available since PG 10) are the most accurate. The `pg_last_xact_replay_timestamp()` method on the standby is older and has a flaw: it only updates when transactions are replayed. On an idle primary, the timestamp freezes and the calculated lag grows, even though the standby is fully caught up.

### Demonstrate the idle-primary problem

Stop pgbench (let it finish or Ctrl+C). Wait 60 seconds, then on NODE1 as the postgres user:

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS replay_lag;
```

**Expected:** The lag shows over a minute even though the standby is fully caught up.

Now check the byte lag from the primary to confirm. On **NODE2** as the postgres user:

```sql
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
```

**Expected:** Zero bytes - the standby is caught up. The time-based method was misleading.

> **Concept:** This is a critical gotcha. In production monitoring, never use `pg_last_xact_replay_timestamp()` as your only lag metric. Combine it with byte lag or use the `replay_lag` column from `pg_stat_replication` on the primary side, which handles idle periods correctly.

---

## Method 3 - Measure Lag via Replication Slot Position

On **NODE2** (primary), as the postgres user:

```sql
SELECT
    slot_name,
    restart_lsn,
    pg_current_wal_lsn() AS current_lsn,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS slot_lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS slot_lag_pretty
FROM pg_replication_slots
WHERE slot_name = 'standby_slot';
```

> **Concept:** Slot lag tells you how much WAL the primary is retaining for this consumer. This metric is critical for disk space monitoring. If a standby goes offline, the slot keeps accumulating WAL on the primary. In production, you should alert when slot lag exceeds a threshold (for example, 1 GB) because it directly translates to disk consumption in `pg_wal/`.

### Simulate a disconnected standby

On **NODE1** (standby):

```bash
sudo systemctl stop postgresql-16
```

Now generate some WAL on **NODE2** (primary), as the postgres user:

```bash
pgbench -c 2 -j 1 -T 30 -h [NODE2_IP] -U postgres labdb
```

After pgbench finishes, check the slot:

```sql
SELECT
    slot_name,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots
WHERE slot_name = 'standby_slot';
```

**Expected:**
```
   slot_name   | active | retained_wal
---------------+--------+--------------
 standby_slot  | f      | 48 MB
```

The slot is `active = f` (standby disconnected) and the primary is holding WAL for it.

### Restart the standby

On **NODE1**:

```bash
sudo systemctl start postgresql-16
```

Wait a few seconds, then check the slot again on **NODE2** as the postgres user:

```sql
SELECT
    slot_name,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots
WHERE slot_name = 'standby_slot';
```

**Expected:** `active = t` and retained WAL drops to near zero.

Exit the postgres user on both nodes:

```bash
exit
```

---

## Summary - When to Use Each Metric

| Metric | Best For | Limitation |
|--------|----------|------------|
| **Byte lag** (`pg_wal_lsn_diff`) | Precise measurement, alerting thresholds | Raw bytes lack time context |
| **Time lag** (`replay_lag` column) | Application-relevant freshness | Requires PG 10+; `pg_last_xact_replay_timestamp` is unreliable when idle |
| **Slot lag** (`restart_lsn` vs `current_wal_lsn`) | Disk space monitoring, detecting disconnected standbys | Measures retained WAL, not strictly the standby's position |

In production, use all three. Byte lag for precision, time lag for SLA tracking, slot lag for disk space protection.

---

## Checkpoint

Before continuing, confirm:
- [ ] You ran pgbench and observed non-zero replication lag
- [ ] You measured lag in bytes using `pg_wal_lsn_diff`
- [ ] You broke down lag into send/write/flush/replay stages
- [ ] You measured time lag using both methods (primary-side and standby-side)
- [ ] You demonstrated the idle-primary timestamp problem
- [ ] You measured slot lag with the standby connected and disconnected
- [ ] You can explain when each metric is most appropriate
- [ ] NODE1 (standby) is running and streaming from NODE2 (primary)

---

**Next:** [Checklist - Self-Assessment](checklist.md)
