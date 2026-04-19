# Exercise 02 - Memory Pressure Analysis

**Time estimate:** 25-30 minutes
**Prerequisites:** BUILD phase complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9 with labdb (pgbench data), postgres user, PGDATA at `/opt/pgsql/data`. Extensions installed: pg_buffercache, pageinspect, pgstattuple.

---

## Objective

Calculate the memory consumption of a PostgreSQL workload and identify which settings to adjust. By the end of this exercise, you should be able to estimate worst-case memory usage for any PostgreSQL instance and interpret the buffer cache and background writer statistics.

---

## Step 1 - Query All Memory-Related GUCs

On **NODE1** (pg-primary), switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -d labdb
```

Query the memory settings:

```sql
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'wal_buffers',
    'temp_buffers',
    'max_connections'
)
ORDER BY name;
```

**Expected:** A table showing each parameter's current value with its unit. Default values on a fresh CentOS install are typically:
- `shared_buffers` = 128MB
- `work_mem` = 4MB
- `maintenance_work_mem` = 64MB
- `effective_cache_size` = 4GB
- `wal_buffers` = 4MB (auto-tuned to 1/32 of shared_buffers)
- `temp_buffers` = 8MB
- `max_connections` = 100

Your lab values may differ if they were tuned during BUILD.

> **Concept:** `shared_buffers` is the main buffer cache - a shared memory region where PostgreSQL caches table and index pages. `work_mem` is per-operation memory for sorts, hashes, and bitmap operations - a single complex query can allocate multiple `work_mem` chunks. `maintenance_work_mem` is used by VACUUM, CREATE INDEX, and ALTER TABLE. `effective_cache_size` does not allocate memory - it tells the planner how much total cache (shared_buffers + OS page cache) to expect, affecting its cost estimates for index scans vs sequential scans.

---

## Step 2 - Calculate Worst-Case Memory Usage

Still in psql, retrieve the raw numeric values:

```sql
SELECT
    current_setting('max_connections') AS max_conn,
    current_setting('shared_buffers') AS shared_buf,
    current_setting('work_mem') AS work,
    current_setting('maintenance_work_mem') AS maint_work,
    current_setting('temp_buffers') AS temp_buf,
    current_setting('autovacuum_max_workers') AS av_workers;
```

**Expected:** A single row with the current values for each setting.

Now calculate the worst-case formula on paper or in your head:

```
Worst-case memory =
    shared_buffers
  + (max_connections x work_mem x estimated_sorts_per_query)
  + (autovacuum_max_workers x maintenance_work_mem)
  + OS overhead (~1-2 GB)
```

For default values: 128MB + (100 x 4MB x 3) + (3 x 64MB) + 1GB = 128MB + 1200MB + 192MB + 1024MB = ~2.5GB.

> **Concept:** The danger with `work_mem` is multiplication. Each backend can allocate `work_mem` multiple times per query - once per sort, hash, or bitmap operation. A query with 3 hash joins uses 3 x `work_mem`. With 100 connections all running such queries simultaneously, that is 100 x 3 x 4MB = 1.2GB from `work_mem` alone. This is why setting `work_mem = 1GB` with 100 connections can cause the OOM killer to fire - worst case is 100 x 3 x 1GB = 300GB.

---

## Step 3 - Measure Cache Hit Ratio

Run a cold query against pgbench_accounts:

```sql
SELECT count(*) FROM pgbench_accounts;
```

**Expected:** Returns the total row count. The first run may be slower as pages are read from disk into shared_buffers.

Run the same query again:

```sql
SELECT count(*) FROM pgbench_accounts;
```

**Expected:** Faster the second time because pages are now cached in shared_buffers or the OS page cache.

Now check the cache hit ratio for the labdb database:

```sql
SELECT
    datname,
    blks_hit,
    blks_read,
    CASE WHEN blks_hit + blks_read = 0 THEN 0
         ELSE round(100.0 * blks_hit / (blks_hit + blks_read), 2)
    END AS hit_ratio_pct
FROM pg_stat_database
WHERE datname = 'labdb';
```

**Expected:** A hit ratio above 90% is typical for a warmed-up database. The `blks_hit` count represents pages found in shared_buffers without going to disk. The `blks_read` count represents pages that had to be read from disk (or OS cache).

> **Concept:** The cache hit ratio is the single most important memory metric. Below 90% means your shared_buffers is too small for your working set - backends are constantly reading from disk. Above 99% is ideal. However, do not blindly increase shared_buffers beyond 25% of total RAM. Beyond that point, the OS page cache becomes less effective and double-buffering wastes memory. On a 16GB server, shared_buffers = 4GB is a good starting point.

---

## Step 4 - Inspect the Buffer Cache Contents

Enable the pg_buffercache extension if not already enabled:

```sql
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
```

Find the top 5 relations consuming buffer cache:

```sql
SELECT
    c.relname,
    c.relkind,
    count(*) AS buffers,
    pg_size_pretty(count(*) * 8192) AS cached_size,
    round(100.0 * count(*) / (SELECT count(*) FROM pg_buffercache WHERE reldatabase IS NOT NULL), 2) AS pct_of_cache
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = c.relfilenode
WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = 'labdb')
GROUP BY c.relname, c.relkind
ORDER BY buffers DESC
LIMIT 5;
```

**Expected:** `pgbench_accounts` will likely dominate the buffer cache because it is the largest table. You will also see its primary key index. The `relkind` column shows `r` for tables and `i` for indexes.

> **Concept:** `pg_buffercache` gives you a real-time snapshot of what is in shared_buffers right now. Each buffer is 8KB (one PostgreSQL page). This is invaluable for capacity planning - if a critical table fits entirely in the buffer cache, queries against it never hit disk. If it does not fit, you either increase shared_buffers or accept that some reads will go to disk (where the OS page cache may still help).

---

## Step 5 - Analyze Background Writer Statistics

Query the background writer stats:

```sql
SELECT
    checkpoints_timed,
    checkpoints_req,
    buffers_checkpoint,
    buffers_clean,
    buffers_backend,
    buffers_alloc,
    maxwritten_clean,
    backend_fsync
FROM pg_stat_bgwriter;
```

**Expected:** A single row with cumulative counters since the last stats reset. Key columns:
- `checkpoints_timed` - checkpoints triggered by `checkpoint_timeout` (scheduled)
- `checkpoints_req` - checkpoints triggered by WAL volume or manual `CHECKPOINT` (forced)
- `buffers_checkpoint` - pages written by the checkpointer process
- `buffers_clean` - pages written by the background writer process
- `buffers_backend` - pages written by regular backend processes (bad - means backends are doing I/O instead of query work)
- `maxwritten_clean` - times the background writer stopped because it hit `bgwriter_lru_maxpages`

> **Concept:** In a healthy system, the checkpointer and background writer should do most of the dirty page writing. If `buffers_backend` is a large percentage of total writes, backends are being forced to evict dirty pages from shared_buffers before they can load new pages - this causes query latency spikes. The fix is usually to increase `bgwriter_lru_maxpages` and `bgwriter_lru_multiplier` so the background writer works harder, or to increase `shared_buffers` so there is less eviction pressure.

Calculate the write distribution:

```sql
SELECT
    round(100.0 * buffers_checkpoint / GREATEST(buffers_checkpoint + buffers_clean + buffers_backend, 1), 2) AS pct_checkpoint,
    round(100.0 * buffers_clean / GREATEST(buffers_checkpoint + buffers_clean + buffers_backend, 1), 2) AS pct_bgwriter,
    round(100.0 * buffers_backend / GREATEST(buffers_checkpoint + buffers_clean + buffers_backend, 1), 2) AS pct_backend
FROM pg_stat_bgwriter;
```

**Expected:** In a healthy system, `pct_backend` should be under 5%. If it is above 10%, the background writer is not keeping up with dirty page generation.

---

## Step 6 - Think: Memory Tuning Scenario

Consider this scenario: your server has 16GB RAM, `shared_buffers = 128MB` (the default), and you see a cache hit ratio of 72%. The database is 10GB.

Answer these questions:
1. Is shared_buffers too small? (Yes - 128MB cannot cache a 10GB working set)
2. What would you set it to? (4GB - 25% of 16GB RAM)
3. After changing shared_buffers to 4GB, what happens to effective_cache_size? (Set it to 12GB - total usable cache including OS page cache)
4. Does changing shared_buffers require a restart? (Yes - it allocates shared memory at startup)

Verify which settings require a restart:

```sql
SELECT name, context
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size');
```

**Expected:**
- `shared_buffers` - context = `postmaster` (requires restart)
- `work_mem` - context = `user` (can be changed per session with SET)
- `maintenance_work_mem` - context = `user` (can be changed per session with SET)
- `effective_cache_size` - context = `user` (can be changed with reload)

> **Concept:** The `context` column in `pg_settings` tells you how a parameter can be changed. `postmaster` means a full server restart is required. `sighup` means you can reload the config with `pg_ctl reload` or `SELECT pg_reload_conf()`. `user` means it can be set per session with `SET work_mem = '64MB';`. In production, always prefer settings that can be changed without a restart. When you must restart, schedule it during a maintenance window.

---

## Step 7 - Clean Up

Exit psql and the postgres user:

```sql
\q
```

```bash
exit
```

---

## Checkpoint

Before continuing, confirm:
- [ ] You queried all memory-related GUCs and understand what each one controls
- [ ] You calculated worst-case memory usage and understand the multiplication danger of `work_mem`
- [ ] You measured the cache hit ratio and know that below 90% is a concern
- [ ] You used `pg_buffercache` to see which relations are consuming buffer cache
- [ ] You queried `pg_stat_bgwriter` and can interpret the write distribution
- [ ] You know which settings require a restart vs a reload vs a session SET
- [ ] You can estimate appropriate `shared_buffers` given a server's total RAM

---

**Next:** [03 - Storage Forensics](03-storage-forensics.md)
