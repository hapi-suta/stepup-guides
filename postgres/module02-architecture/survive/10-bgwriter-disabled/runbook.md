# Runbook 10 - Background Writer Disabled

| Field         | Value                                        |
|---------------|----------------------------------------------|
| Scenario      | bgwriter disabled, backends doing direct I/O  |
| Severity      | MEDIUM                                       |
| Recovery Time | 5-10 minutes                                 |
| Blast Radius  | All queries experience increased latency      |

---

## Fix Path

### Step 1 - Check bgwriter Statistics

```bash
sudo -iu postgres
```
```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT buffers_checkpoint,
         buffers_clean,
         buffers_backend,
         buffers_backend_fsync
  FROM pg_stat_bgwriter;
"
```

Expected output (yours will differ):

```
 buffers_checkpoint | buffers_clean | buffers_backend | buffers_backend_fsync
--------------------+---------------+-----------------+-----------------------
              12845 |             0 |            9372 |                     0
(1 row)
```

Key observation: `buffers_backend` is high while `buffers_clean` is 0. This means the background writer is not cleaning dirty buffers, forcing backend processes to do it themselves.

### Step 2 - Check bgwriter Configuration

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SHOW bgwriter_lru_maxpages;
"
```

Expected output:

```
 bgwriter_lru_maxpages
-----------------------
 0
(1 row)
```

The value is `0`, which completely disables the background writer's buffer cleaning.

Also check the checkpoint interval.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SHOW checkpoint_timeout;
"
```

The value is `30min` - far too long. With bgwriter disabled and checkpoints 30 minutes apart, dirty buffers pile up and backends must write them out.

### Step 3 - Re-enable the Background Writer

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  ALTER SYSTEM SET bgwriter_lru_maxpages = 100;
"
```

The default value is 100 pages per round. This means the bgwriter will clean up to 100 dirty buffers each cycle (every `bgwriter_delay` milliseconds, default 200ms).

### Step 4 - Restore Checkpoint Timeout

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  ALTER SYSTEM SET checkpoint_timeout = '5min';
"
```

The default is 5 minutes. This ensures dirty buffers are flushed periodically even if the bgwriter falls behind.

### Step 5 - Reload Configuration

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT pg_reload_conf();
"
```

### Step 6 - Verify Settings Applied

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SHOW bgwriter_lru_maxpages;
  SHOW checkpoint_timeout;
"
```

Expected output:

```
 bgwriter_lru_maxpages
-----------------------
 100
(1 row)

 checkpoint_timeout
--------------------
 5min
(1 row)
```

Confirm `bgwriter_lru_maxpages` is 100 (or a reasonable non-zero value) and `checkpoint_timeout` is 5min or similar.

### Step 7 - Force a Checkpoint

Flush currently dirty buffers immediately.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "CHECKPOINT;"
```

### Step 8 - Verify bgwriter Is Working

Reset stats, run a small workload, and check that `buffers_clean` is now increasing.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT pg_stat_reset_shared('bgwriter');
"
```

Run a quick pgbench.

```bash
/usr/pgsql-16/bin/pgbench -c 2 -j 1 -T 10 -p 5432 labdb
```

`-c 2` sets 2 concurrent clients, `-j 1` uses 1 worker thread, `-T 10` runs for 10 seconds, `-p 5432` connects to port 5432.

Check the stats again.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT buffers_clean,
         buffers_backend,
         buffers_checkpoint
  FROM pg_stat_bgwriter;
"
```
```bash
exit
```

Expected output (yours will differ):

```
 buffers_clean | buffers_backend | buffers_checkpoint
---------------+-----------------+--------------------
           247 |              38 |                  0
(1 row)
```

You should see `buffers_clean > 0`, confirming the bgwriter is active.

---

## Revision Concepts

### Three Writers in PostgreSQL

PostgreSQL has three processes that write dirty (modified) buffers from shared_buffers to disk:

| Writer          | When It Writes                                   | Impact on Queries |
|-----------------|--------------------------------------------------|-------------------|
| **bgwriter**    | Continuously, in the background                  | None - runs asynchronously |
| **checkpointer**| At checkpoint intervals or when triggered         | Can cause I/O spikes |
| **backend**     | When a backend needs a buffer but all are dirty   | Directly adds latency to the query |

The goal is to minimize backend writes. Backends should find clean buffers ready to use, not have to flush dirty ones first.

### Background Writer (bgwriter)

The bgwriter runs in a loop:
1. Sleep for `bgwriter_delay` (default: 200ms)
2. Scan the buffer pool for dirty buffers
3. Write up to `bgwriter_lru_maxpages` (default: 100) dirty buffers
4. Repeat

Key parameters:
- `bgwriter_delay` - sleep time between rounds (default 200ms)
- `bgwriter_lru_maxpages` - max buffers to write per round (0 = disabled)
- `bgwriter_lru_multiplier` - how many buffers to clean relative to recent demand (default 2.0)

Setting `bgwriter_lru_maxpages = 0` completely disables the bgwriter. This forces all buffer cleaning onto checkpoints and backends.

### Checkpointer

The checkpointer runs on a schedule (`checkpoint_timeout`, default 5 min) or when WAL reaches `max_wal_size`. At checkpoint time, it writes ALL dirty buffers to disk. With a 30-minute timeout:
- Dirty buffers accumulate for 30 minutes
- The checkpoint I/O spike is massive
- Between checkpoints, backends must self-serve

### Why Backend Writes Are Bad

When a backend process needs a clean buffer and cannot find one, it must:
1. Pick a dirty buffer
2. Write it to disk (synchronous I/O)
3. Only then can it load the page it needs

This adds I/O latency directly to the query that triggered it. The user query stalls while waiting for a disk write that has nothing to do with their data. This is why `buffers_backend` growing is a red flag.

### buffers_backend_fsync

If `buffers_backend_fsync > 0`, it means backends had to call fsync themselves - even worse than regular backend writes. This indicates the OS write-back cache is also overwhelmed.

---

## Interview Discussion

**Q: What is the background writer and why does it matter?**

The bgwriter continuously cleans dirty buffers in shared_buffers by writing them to disk in the background. This ensures that when a backend process needs a buffer, it can find a clean one without having to do a synchronous write first. Without the bgwriter, backends experience unpredictable latency spikes when they must flush dirty pages themselves.

**Q: How do you detect that backends are doing too many writes?**

Check `pg_stat_bgwriter`. If `buffers_backend` is growing much faster than `buffers_clean`, backends are doing the work that the bgwriter should handle. A healthy system has `buffers_clean >> buffers_backend`. Also monitor `buffers_backend_fsync` - any non-zero value is a serious I/O concern.

**Q: What is the relationship between bgwriter and checkpointer?**

They are separate processes with different goals. The bgwriter proactively cleans dirty buffers to keep a supply of clean buffers available. The checkpointer periodically writes ALL dirty buffers to create a consistent recovery point. The bgwriter smooths out I/O; the checkpointer creates crash recovery guarantees. Both reduce backend writes, but through different mechanisms.

**Q: How would you tune the bgwriter for a write-heavy workload?**

Increase `bgwriter_lru_maxpages` (e.g., 200-500) so it cleans more buffers per round. Decrease `bgwriter_delay` (e.g., 100ms) so it runs more frequently. Increase `bgwriter_lru_multiplier` (e.g., 4.0) so it stays ahead of demand. Monitor `buffers_backend` after each change. The goal is to keep `buffers_backend` near zero.

**Q: What happens during a checkpoint and how does checkpoint_timeout affect performance?**

At checkpoint time, PostgreSQL writes all dirty buffers to disk and records the checkpoint location in pg_control. A longer `checkpoint_timeout` means more dirty buffers accumulate, resulting in a larger I/O spike when the checkpoint finally runs. `checkpoint_completion_target` (default 0.9) spreads the writes over 90% of the interval to avoid a sudden burst. For most systems, 5-15 minutes is a reasonable checkpoint_timeout.
