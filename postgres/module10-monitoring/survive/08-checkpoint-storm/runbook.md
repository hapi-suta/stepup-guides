# Scenario 08 - Checkpoint Storm

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Excessive checkpoints detected.
pg_stat_bgwriter shows high requested checkpoint counts.
Checkpoints are happening every few seconds.
Write performance is degraded due to constant flushing.
```

---

## Key Concepts for Revision

- **What is a checkpoint?** - A checkpoint is when PostgreSQL flushes all dirty (modified) pages from shared buffers to disk. This ensures that the WAL before the checkpoint can be recycled. Checkpoints are expensive because they involve heavy disk I/O - writing potentially gigabytes of data to the data files all at once.

- **checkpoint_completion_target** - Controls how quickly a checkpoint tries to finish, as a fraction of the time until the next checkpoint. Default is `0.9`, meaning the checkpoint spreads its writes over 90% of the interval. Setting it to `0.1` means the checkpoint tries to finish in 10% of the interval, creating a massive I/O burst followed by idle time. This spiky pattern is harmful to query performance.

- **max_wal_size** - The maximum amount of WAL that can accumulate between checkpoints. Default is `1GB`. When WAL reaches this size, PostgreSQL forces a checkpoint (a "requested" checkpoint). Setting it to `32MB` means a checkpoint is forced after every 32MB of WAL - on a busy system, this can mean checkpoints every few seconds.

- **checkpoint_timeout** - The maximum time between automatic checkpoints. Default is `5min`. Setting it to `15s` means a time-based checkpoint fires every 15 seconds regardless of WAL volume.

- **pg_stat_bgwriter** - This view tracks checkpoint activity. `checkpoints_timed` counts time-based checkpoints. `checkpoints_req` counts WAL-size-triggered checkpoints. A high `checkpoints_req` relative to `checkpoints_timed` means `max_wal_size` is too small for the write volume.

---

## Diagnostic Steps

### Step 1 - Connect to PostgreSQL

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Check checkpoint frequency in pg_stat_bgwriter

```sql
SELECT checkpoints_timed,
       checkpoints_req,
       buffers_checkpoint,
       buffers_clean,
       checkpoint_write_time,
       checkpoint_sync_time
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | buffers_checkpoint | buffers_clean | checkpoint_write_time | checkpoint_sync_time
-------------------+-----------------+--------------------+---------------+-----------------------+----------------------
                 5 |              42 |             125000 |          3200 |                 85432 |                12345
(1 row)
```

A high `checkpoints_req` count (requested checkpoints) compared to `checkpoints_timed` means WAL-triggered checkpoints are dominating. This indicates `max_wal_size` is too small.

### Step 3 - Check the current checkpoint parameters

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE name IN (
  'checkpoint_completion_target',
  'max_wal_size',
  'checkpoint_timeout'
)
ORDER BY name;
```

Expected output (yours will differ):

```
            name             | setting | unit
-----------------------------+---------+------
 checkpoint_completion_target| 0.1     |
 checkpoint_timeout          | 15      | s
 max_wal_size                | 32      | MB
(3 rows)
```

All three values are set to cause constant, aggressive checkpoints.

### Step 4 - Check the PostgreSQL log for checkpoint warnings

```bash
exit
```

```bash
sudo -iu postgres
```

```bash
grep -i "checkpoint" /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log | tail -10
```

Expected output (yours will differ):

```
2026-04-19 11:10:05 UTC LOG:  checkpoint starting: wal
2026-04-19 11:10:06 UTC LOG:  checkpoint complete: wrote 450 buffers (3.4%); ...
2026-04-19 11:10:08 UTC LOG:  checkpoints are occurring too frequently (3 seconds apart)
2026-04-19 11:10:08 UTC HINT:  Consider increasing the configuration parameter "max_wal_size".
```

The `checkpoints are occurring too frequently` warning with the hint about `max_wal_size` confirms the problem.

```bash
exit
```

---

## Resolution

### Step 1 - Reset checkpoint parameters to defaults

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM RESET checkpoint_completion_target;
```

```sql
ALTER SYSTEM RESET max_wal_size;
```

```sql
ALTER SYSTEM RESET checkpoint_timeout;
```

### Step 2 - Reload the configuration

```sql
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 3 - Verify parameters are back to defaults

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE name IN (
  'checkpoint_completion_target',
  'max_wal_size',
  'checkpoint_timeout'
)
ORDER BY name;
```

Expected output (yours will differ):

```
            name             | setting | unit
-----------------------------+---------+------
 checkpoint_completion_target| 0.9     |
 checkpoint_timeout          | 300     | s
 max_wal_size                | 1024    | MB
(3 rows)
```

`checkpoint_completion_target` is `0.9`, `max_wal_size` is `1024` MB (1GB), and `checkpoint_timeout` is `300` seconds (5 minutes).

### Step 4 - Reset the bgwriter stats to start fresh

```sql
SELECT pg_stat_reset_shared('bgwriter');
```

Expected output (yours will differ):

```
 pg_stat_reset_shared
----------------------

(1 row)
```

This resets the checkpoint counters so you can monitor from a clean baseline.

### Step 5 - Wait briefly and confirm checkpoint frequency is reasonable

Wait about 30 seconds, then check again.

```sql
SELECT checkpoints_timed, checkpoints_req
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req
-------------------+-----------------
                 0 |               0
(1 row)
```

With proper settings, you should see very few or zero checkpoints in 30 seconds. Previously, you would have seen many.

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- checkpoint_completion_target is 0.9
- max_wal_size is 1024 MB or more
- checkpoint_timeout is 300s or more
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **What is the performance impact of too-frequent checkpoints?** - Each checkpoint flushes dirty pages to disk. With `checkpoint_completion_target=0.1`, all the writes happen in a burst, causing I/O spikes that slow down concurrent queries. With `max_wal_size=32MB`, the system never builds up enough WAL buffer, so checkpoints fire constantly. The combined effect is sustained high I/O utilization with no quiet periods for normal query I/O.

2. **How do you calculate the right max_wal_size for a workload?** - Monitor `checkpoints_req` vs `checkpoints_timed` over a normal workload period. If `checkpoints_req` is high, `max_wal_size` is too small. A good starting point is 2-4GB for OLTP systems. For write-heavy systems, 8-16GB is common. The tradeoff is recovery time - more WAL between checkpoints means longer crash recovery.

3. **What does checkpoint_completion_target actually control?** - It controls the pacing of dirty page writes. With `target=0.9` and a `timeout=5min`, the checkpoint spreads its writes over 4.5 minutes (90% of 5 minutes). This smooths I/O over time. With `target=0.1`, it tries to write everything in 30 seconds (10% of 5 minutes), creating a burst. The default of 0.9 is correct for almost all workloads.

4. **How do you know if checkpoints are causing your performance problem vs something else?** - Correlate `pg_stat_bgwriter.checkpoint_write_time` and `checkpoint_sync_time` with query latency spikes. Also check `pg_stat_io` (PostgreSQL 16+) for `context = 'normal'` vs `context = 'vacuum'` I/O. If checkpoint I/O correlates with latency spikes, checkpoints are the culprit. If not, look elsewhere.

5. **What is the relationship between checkpoints and WAL archiving?** - Checkpoints determine when WAL segments can be recycled. After a checkpoint completes, WAL segments before the checkpoint are eligible for recycling (or archiving). More frequent checkpoints mean more frequent WAL recycling, which reduces disk usage in `pg_wal` but increases I/O. Less frequent checkpoints let `pg_wal` grow larger but reduce I/O overhead.
