# Scenario 07 - Checkpoints Too Frequent

**Severity:** MEDIUM
**Expected Recovery Time:** 8-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Disk I/O is spiking every few seconds.
The PostgreSQL log shows frequent 'checkpoint starting'
messages. Write performance is degraded because
checkpoints are running almost continuously.
The ops team suspects a configuration change.
```

---

## Key Concepts for Revision

- **What is a checkpoint?** - A checkpoint flushes all dirty pages from shared_buffers to disk and writes a checkpoint record to WAL. After a checkpoint, PostgreSQL can recycle WAL files before that point because the data is safely on disk. Checkpoints are essential for crash recovery - they define the starting point for WAL replay.

- **max_wal_size controls checkpoint frequency** - When the total WAL generated since the last checkpoint exceeds `max_wal_size`, PostgreSQL triggers a checkpoint. At 32MB, even a modest write workload fills this quickly, causing checkpoints every few seconds. The default is 1GB. Production systems often use 2-8GB.

- **checkpoint_completion_target spreads I/O** - This setting (0.0 to 1.0) controls what fraction of the checkpoint interval is used to write dirty pages. At 0.1, PostgreSQL tries to write all dirty pages in 10% of the time between checkpoints, creating intense I/O bursts. At 0.9 (recommended), writes are spread over 90% of the interval, smoothing I/O.

- **checkpoint_timeout is the time-based trigger** - Even if `max_wal_size` is not reached, a checkpoint occurs every `checkpoint_timeout` seconds. Default is 5 minutes. Setting it to 15 seconds causes checkpoints at least that often regardless of WAL volume.

- **pg_stat_bgwriter tracks checkpoint frequency** - The `checkpoints_timed` and `checkpoints_req` columns show how many checkpoints were triggered by timeout vs WAL size. High `checkpoints_req` means WAL-triggered checkpoints are dominant, indicating `max_wal_size` is too small.

---

## Diagnostic Steps

### Step 1 - Check the PostgreSQL log for checkpoint messages

```bash
sudo -iu postgres
```

```bash
tail -30 /opt/pgsql/log/postgresql-*.log | grep -i checkpoint
```

Expected output (yours will differ):

```
LOG:  checkpoint starting: wal
LOG:  checkpoint complete: wrote 150 buffers (0.9%); ...
LOG:  checkpoint starting: time
LOG:  checkpoint complete: wrote 80 buffers (0.5%); ...
LOG:  checkpoint starting: wal
...
```

Multiple checkpoint messages within seconds of each other confirms the problem.

### Step 2 - Check pg_stat_bgwriter for checkpoint statistics

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT
  checkpoints_timed,
  checkpoints_req,
  buffers_checkpoint,
  buffers_clean,
  buffers_backend
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | buffers_checkpoint | buffers_clean | buffers_backend
-------------------+-----------------+--------------------+---------------+-----------------
                 5 |              12 |               2400 |             0 |             150
(1 row)
```

High `checkpoints_req` (WAL-triggered) relative to `checkpoints_timed` confirms `max_wal_size` is too small.

### Step 3 - Check current checkpoint settings

```sql
SHOW max_wal_size;
```

Expected output:

```
 max_wal_size
--------------
 32MB
(1 row)
```

```sql
SHOW checkpoint_completion_target;
```

Expected output:

```
 checkpoint_completion_target
------------------------------
 0.1
(1 row)
```

```sql
SHOW checkpoint_timeout;
```

Expected output:

```
 checkpoint_timeout
--------------------
 15s
(1 row)
```

All three values are problematic. 32MB WAL size, 10% completion target, and 15-second timeout create near-continuous checkpointing.

### Step 4 - Confirm settings are in postgresql.auto.conf

```sql
\q
```

```bash
grep -E 'max_wal_size|checkpoint_completion_target|checkpoint_timeout' /opt/pgsql/data/postgresql.auto.conf
```

Expected output:

```
max_wal_size = '32MB'
checkpoint_completion_target = '0.1'
checkpoint_timeout = '15s'
```

---

## Resolution

### Step 1 - Set reasonable checkpoint parameters

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM SET max_wal_size = '1GB';
```

Expected output:

```
ALTER SYSTEM
```

1GB is the default and a good starting point. Increase to 2-4GB for write-heavy workloads.

```sql
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
```

Expected output:

```
ALTER SYSTEM
```

0.9 spreads checkpoint I/O over 90% of the interval, preventing I/O spikes.

```sql
ALTER SYSTEM SET checkpoint_timeout = '5min';
```

Expected output:

```
ALTER SYSTEM
```

5 minutes is the default. Some production systems use 15-30 minutes.

### Step 2 - Reload configuration

```sql
SELECT pg_reload_conf();
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 3 - Verify the new settings

```sql
SHOW max_wal_size;
```

Expected output:

```
 max_wal_size
--------------
 1GB
(1 row)
```

```sql
SHOW checkpoint_completion_target;
```

Expected output:

```
 checkpoint_completion_target
------------------------------
 0.9
(1 row)
```

```sql
SHOW checkpoint_timeout;
```

Expected output:

```
 checkpoint_timeout
--------------------
 5min
(1 row)
```

### Step 4 - Reset checkpoint statistics to monitor going forward

```sql
SELECT pg_stat_reset_shared('bgwriter');
```

Expected output:

```
 pg_stat_reset_shared
----------------------

(1 row)
```

```sql
\q
```

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- max_wal_size is at least 256MB
- checkpoint_completion_target is at least 0.5
- checkpoint_timeout is at least 60 seconds
- postgresql.auto.conf has no aggressive checkpoint settings

---

## Interview Discussion Points

1. **What is the difference between checkpoints_timed and checkpoints_req?** - `checkpoints_timed` counts checkpoints triggered by the `checkpoint_timeout` timer expiring. `checkpoints_req` counts checkpoints triggered by WAL reaching `max_wal_size` or explicit `CHECKPOINT` commands. In a well-tuned system, almost all checkpoints should be `checkpoints_timed` - meaning the timeout triggers before WAL fills up. If `checkpoints_req` dominates, `max_wal_size` is too small for the write rate.

2. **How do frequent checkpoints affect performance?** - Three ways: (1) Disk I/O spikes from flushing dirty pages. (2) WAL amplification - more frequent checkpoints mean more full-page writes (FPW) in WAL, because every page modified for the first time after a checkpoint gets a full-page image written to WAL. (3) CPU overhead from the checkpoint process scanning shared_buffers for dirty pages.

3. **What is full-page writes and how do checkpoints relate?** - After a crash, PostgreSQL replays WAL from the last checkpoint. If a crash happens mid-write of an 8kB page, the page on disk may be partially written (torn page). Full-page writes (FPW) solve this by writing the entire page to WAL the first time it is modified after a checkpoint. During recovery, the full page image is used instead of the potentially torn on-disk page. More frequent checkpoints mean more FPW entries, increasing WAL volume.

4. **What max_wal_size would you set for a write-heavy OLTP system?** - Start with 2GB and monitor. If `checkpoints_req` is still high, increase to 4-8GB. The trade-off: larger `max_wal_size` means fewer checkpoints but longer recovery time after a crash (more WAL to replay). For systems that can tolerate 5-10 minute recovery, 4-8GB is common.

5. **How do you monitor checkpoint impact in real-time?** - Check `pg_stat_bgwriter` for checkpoint counts and buffer writes. Monitor WAL generation rate with `pg_stat_wal` (PG 14+). Watch `log_checkpoints = on` in postgresql.conf for detailed checkpoint timing in the server log. Monitor disk I/O with `iostat` - checkpoint spikes show as periodic write bursts.
