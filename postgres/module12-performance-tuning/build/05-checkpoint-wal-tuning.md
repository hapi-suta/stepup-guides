# Guide 05 - Checkpoint and WAL Tuning

Learn how PostgreSQL checkpoints work, why too-frequent checkpoints hurt write performance, and how to tune WAL parameters to reduce I/O amplification on write-heavy workloads.

**Server:** NODE1 only

---

## What You Will Learn

- What a checkpoint is and why it matters for write performance
- How checkpoint_timeout, checkpoint_completion_target, max_wal_size, and min_wal_size interact
- What WAL write amplification is and how wal_buffers helps
- How to read pg_stat_bgwriter to measure checkpoint behavior

---

## 1. Connect to the Server

SSH into NODE1.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

---

## 2. What Is a Checkpoint?

PostgreSQL uses WAL (Write-Ahead Log) for crash safety. When data pages change, they are first written to WAL before being written to the actual data files. A **checkpoint** is the moment when PostgreSQL flushes all dirty shared_buffers pages to disk, creating a known-good recovery point.

Until a checkpoint completes, crash recovery must replay WAL from the previous checkpoint. This means:

- Frequent checkpoints = more I/O during the checkpoint but less WAL to replay on crash
- Infrequent checkpoints = less background I/O but longer crash recovery

Check the current checkpoint-related settings.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('checkpoint_timeout','checkpoint_completion_target','max_wal_size','min_wal_size','wal_buffers') ORDER BY name;"
```

Expected output (yours will differ):

```
            name             | setting | unit
-----------------------------+---------+------
 checkpoint_completion_target| 0.9     |
 checkpoint_timeout          | 300     | s
 max_wal_size                | 1024    | MB
 min_wal_size                | 80      | MB
 wal_buffers                 | 512     | 8kB
(5 rows)
```

> **Concept - Checkpoint Frequency Triggers**: A checkpoint fires when either (1) `checkpoint_timeout` seconds have passed since the last checkpoint, or (2) WAL has grown by `max_wal_size` since the last checkpoint. Whichever comes first wins. In a write-heavy workload, `max_wal_size` is usually the trigger. In a quiet workload, `checkpoint_timeout` fires first.

---

## 3. checkpoint_timeout - Time Between Checkpoints

The default is 5 minutes (300 seconds). For most write-heavy applications, 15 minutes (900s) to 30 minutes (1800s) is better.

A longer timeout means:

- Less frequent checkpoint I/O bursts
- More WAL to replay on crash (proportionally longer crash recovery)
- Requires a larger `max_wal_size` to give WAL room to accumulate

Change checkpoint_timeout to 15 minutes using ALTER SYSTEM.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET checkpoint_timeout = '15min';"
```

Expected output:

```
ALTER SYSTEM
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET max_wal_size = '2GB';"
```

Expected output:

```
ALTER SYSTEM
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET min_wal_size = '256MB';"
```

Expected output:

```
ALTER SYSTEM
```

Reload to apply the changes (no restart needed for these parameters).

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

Verify the change.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW checkpoint_timeout;"
```

Expected output:

```
 checkpoint_timeout
--------------------
 15min
(1 row)
```

---

## 4. checkpoint_completion_target - Spread the I/O

When a checkpoint fires, PostgreSQL must flush all dirty pages. If it flushes everything immediately, it causes a sharp I/O spike that slows down concurrent queries.

`checkpoint_completion_target` tells PostgreSQL to spread the dirty page writes over a fraction of the `checkpoint_timeout` interval. A value of `0.9` means PostgreSQL aims to finish writing all dirty pages by the time 90% of `checkpoint_timeout` has elapsed.

The default of `0.9` is correct for most workloads. Lower values (0.5) mean faster, more bursty writes. Never set it above 0.99.

Verify the setting.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW checkpoint_completion_target;"
```

Expected output:

```
 checkpoint_completion_target
------------------------------
 0.9
(1 row)
```

> **Concept - I/O Spreading Math**: With `checkpoint_timeout = 15min` and `checkpoint_completion_target = 0.9`, PostgreSQL spreads dirty page writes over 15 * 0.9 = 13.5 minutes. This turns what would be a 30-second I/O burst into a 13.5-minute gentle trickle. Your application queries compete with checkpoint I/O far less.

---

## 5. max_wal_size and min_wal_size

WAL files are recycled rather than deleted when they are no longer needed. `max_wal_size` is the upper bound on how much WAL disk space to retain. `min_wal_size` is the amount PostgreSQL will keep pre-allocated so it never needs to create new files from scratch.

Verify the settings.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW max_wal_size;"
```

Expected output:

```
 max_wal_size
--------------
 2GB
(1 row)
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW min_wal_size;"
```

Expected output:

```
 min_wal_size
--------------
 256MB
(1 row)
```

Check current WAL directory usage.

```
exit
```

```
sudo du -sh /opt/pgsql/data/pg_wal/
```

Expected output (yours will differ):

```
48M     /opt/pgsql/data/pg_wal/
```

```
sudo ls /opt/pgsql/data/pg_wal/ | head -5
```

Expected output (yours will differ):

```
000000010000000000000001
000000010000000000000002
000000010000000000000003
```

Each WAL file is 16MB by default. At `min_wal_size = 256MB`, PostgreSQL keeps about 16 WAL files pre-allocated at all times.

---

## 6. wal_buffers - Memory for Pending WAL Writes

`wal_buffers` is a shared memory area where in-progress WAL records wait before being written to disk. The default is `-1` which auto-sizes to 1/32 of `shared_buffers` (with a minimum of 64kB and a cap of 16MB).

Check the current value.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW wal_buffers;"
```

Expected output:

```
 wal_buffers
-------------
 4MB
(1 row)
```

For most workloads, the automatic 16MB cap is sufficient. For very high-concurrency write workloads, you might see benefit from 32-64MB. This requires a restart.

> **Concept - WAL Write Amplification**: Every data change is first written to WAL, then eventually to the data file. So each change is written twice (WAL + heap). Full-page writes (FPW) add a third write: when a page is modified for the first time after a checkpoint, PostgreSQL writes the entire 8kB page into WAL (not just the changed bytes). This protects against partial-page writes during a crash. `full_page_writes = on` is the default and should never be disabled in production.

---

## 7. Read pg_stat_bgwriter for Checkpoint Statistics

`pg_stat_bgwriter` accumulates statistics about checkpoint behavior since the last reset.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT checkpoints_timed, checkpoints_req, checkpoint_write_time, checkpoint_sync_time, buffers_checkpoint, buffers_clean, buffers_backend, maxwritten_clean FROM pg_stat_bgwriter;"
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | checkpoint_write_time | checkpoint_sync_time | buffers_checkpoint | buffers_clean | buffers_backend | maxwritten_clean
-------------------+-----------------+-----------------------+----------------------+--------------------+---------------+-----------------+------------------
                 3 |               0 |                1234.5 |                 45.2 |                150 |            20 |               8 |                0
(1 row)
```

Key columns to watch:

- `checkpoints_timed` - checkpoints fired by `checkpoint_timeout` (good - planned)
- `checkpoints_req` - checkpoints fired by WAL size limit (bad if high - WAL is filling up too fast, raise `max_wal_size`)
- `checkpoint_write_time` - milliseconds spent writing dirty pages (should be gradual)
- `checkpoint_sync_time` - milliseconds spent in fsync (sudden spikes mean I/O bottleneck)
- `buffers_backend` - buffers written directly by backends (bad - means checkpoint is not keeping up)
- `maxwritten_clean` - how often bgwriter stopped because it hit `bgwriter_lru_maxpages` limit

> **Concept - buffers_backend Warning**: When `buffers_backend` is high, backends (your application queries) are being forced to write dirty pages themselves because the checkpoint and bgwriter cannot keep up. This is a sign that your write load exceeds your checkpoint configuration. Raise `max_wal_size`, lower `checkpoint_completion_target`, or tune `bgwriter_lru_maxpages`.

---

## 8. Simulate Checkpoint Pressure and Observe

Generate some write load to create dirty pages.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
BEGIN;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id <= 10000;
COMMIT;
```

Expected output:

```
BEGIN
UPDATE 10000
COMMIT
```

Force a checkpoint manually.

```sql
CHECKPOINT;
```

Expected output:

```
CHECKPOINT
```

Check the bgwriter stats again to see the checkpoint recorded.

```sql
SELECT checkpoints_timed, checkpoints_req, buffers_checkpoint
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | buffers_checkpoint
-------------------+-----------------+--------------------
                 4 |               0 |                210
(1 row)
```

`buffers_checkpoint` increased by 60 (the pages written during the manual checkpoint).

Check the WAL location before and after the write burst.

```sql
SELECT pg_current_wal_lsn();
```

Expected output (yours will differ):

```
 pg_current_wal_lsn
--------------------
 0/3000000
(1 row)
```

```sql
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0'));
```

Expected output (yours will differ):

```
 pg_size_pretty
----------------
 48 MB
(1 row)
```

```
\q
```

```
exit
```

---

## Checkpoint

By the end of this guide you should be able to:

- [ ] Explain what a checkpoint is and when it fires
- [ ] Describe the role of checkpoint_timeout, checkpoint_completion_target, max_wal_size, and min_wal_size
- [ ] Identify the difference between checkpoints_timed and checkpoints_req in pg_stat_bgwriter
- [ ] Explain what WAL write amplification and full-page writes are
- [ ] Read pg_stat_bgwriter and identify a write-pressure warning from buffers_backend

---

**Proceed to:** [Guide 06 - OS-Level Diagnostics](./06-os-diagnostics.md)
