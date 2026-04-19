# Build 02: Memory Architecture

**Duration:** 45 minutes
**Node:** NODE1 only
**Prerequisites:** PostgreSQL 16 running on NODE1. Lab 2.1 completed.

In this lab you will explore PostgreSQL's memory subsystem - the shared memory that all backends use together, and the per-process memory that each connection allocates on its own. Understanding how PostgreSQL uses memory is critical for tuning performance and avoiding out-of-memory issues.

---

## 1. Shared Memory Overview

**Run on NODE1 (pg-primary):**

Shared memory is a block of memory allocated when PostgreSQL starts. Every backend (connection) reads and writes to this same shared pool. Let's look at the key settings that control it.

First, switch to the `postgres` OS user.

```bash
sudo -i -u postgres
```

**You are now the postgres user.**

Connect to PostgreSQL.

```bash
psql
```

We'll start by checking memory settings on the `postgres` database, then switch to `labdb` for the buffer cache exercises.

Check the `shared_buffers` setting. This is the pool of memory shared by all backends for caching data pages. When PostgreSQL reads a page from disk, it lands here so other backends can reuse it without going back to disk.

```sql
SHOW shared_buffers;
```

Expected output (yours will differ):

```
 shared_buffers
----------------
 128MB
(1 row)
```

Check the `work_mem` setting. This is the amount of memory available per-operation for sorts and hash tables. Each backend - and each operation within that backend - can use up to this much memory.

```sql
SHOW work_mem;
```

Expected output:

```
 work_mem
----------
 4MB
(1 row)
```

Check the `maintenance_work_mem` setting. This is the memory budget for maintenance operations like VACUUM and CREATE INDEX. These operations are infrequent but memory-hungry, so this is usually set higher than `work_mem`.

```sql
SHOW maintenance_work_mem;
```

Expected output:

```
 maintenance_work_mem
----------------------
 64MB
(1 row)
```

Check the `effective_cache_size` setting. This is a hint to the query planner about how much total cache (shared_buffers + OS page cache) is available. It does not allocate any memory - it only influences query plans.

```sql
SHOW effective_cache_size;
```

Expected output (yours will differ):

```
 effective_cache_size
----------------------
 4GB
(1 row)
```

Check the `wal_buffers` setting. This is the memory used to buffer WAL (write-ahead log) data before it is flushed to disk. PostgreSQL auto-tunes this based on shared_buffers if you leave it at the default of `-1`.

```sql
SHOW wal_buffers;
```

Expected output (yours will differ):

```
 wal_buffers
-------------
 4MB
(1 row)
```

> **Concept: Shared vs. Private Memory**
> PostgreSQL memory splits into two zones. Shared memory (shared_buffers, wal_buffers) is allocated once at startup and used by all connections. Private memory (work_mem, temp_buffers, maintenance_work_mem) is allocated per-backend, per-operation. Tuning shared memory is about total size; tuning private memory is about multiplication - how many connections times how many operations.

---

## 2. Install pg_buffercache Extension

**Run on NODE1 (pg-primary):**

The `pg_buffercache` extension lets you peek inside shared_buffers to see exactly which data pages are cached right now. It ships with PostgreSQL but is not enabled by default.

You should still be connected to `psql` as the postgres user. If not, reconnect.

Install the extension.

```sql
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
```

Expected output:

```
CREATE EXTENSION
```

Verify the extension is installed. The `\dx` command lists installed extensions.

```sql
\dx pg_buffercache
```

Expected output:

```
                             List of installed extensions
      Name       | Version | Schema |              Description
-----------------+---------+--------+---------------------------------------
 pg_buffercache  | 1.4     | public | examine the shared buffer cache
(1 row)
```

> **Concept: Extensions as X-Ray Vision**
> PostgreSQL ships with many contrib extensions that expose internals. `pg_buffercache` shows shared memory contents, `pg_stat_statements` tracks query performance, and `pageinspect` lets you look at raw page headers. These are your diagnostic tools - install them on every server you manage.

---

## 3. Inspect the Buffer Cache

**Run on NODE1 (pg-primary):**

The `pgbench_accounts` table lives in `labdb` - that's where it was created during the backup-pitr lab. We need to connect to that database before we can inspect its cached pages.

First, quit psql.

```sql
\q
```

Reconnect to `labdb`.

```bash
psql -d labdb
```

Now let's look at what is currently sitting in shared_buffers. Each buffer slot holds one 8KB page (one PostgreSQL page).

Run the following query. It joins `pg_buffercache` with `pg_class` to map buffer slots back to table and index names.

```sql
SELECT c.relname, count(*) AS buffers,
       pg_size_pretty(count(*) * 8192) AS cached_size
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = c.relfilenode
WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY c.relname
ORDER BY buffers DESC
LIMIT 10;
```

Expected output (yours will differ):

```
        relname        | buffers | cached_size
-----------------------+---------+-------------
 pgbench_accounts      |    1640 | 12 MB
 pgbench_accounts_pkey |     276 | 2208 kB
 pgbench_tellers       |       2 | 16 kB
 pgbench_branches      |       1 | 8192 bytes
(4 rows)
```

Each row shows how many 8KB buffer slots a particular relation occupies. The `cached_size` column converts that count to a human-readable size by multiplying by 8192 bytes (the page size).

> **Concept: The 8KB Page**
> PostgreSQL stores all data in fixed-size 8KB pages. Whether it is a table row, an index entry, or a TOAST chunk - everything lives in 8KB pages. When PostgreSQL needs a row, it reads the entire 8KB page into shared_buffers. This is the fundamental unit of I/O in PostgreSQL.

---

## 4. Watch the Cache in Action

**Run on NODE1 (pg-primary):**

Let's see the cache change in real time. First, note the current buffer count for `pgbench_accounts` from the query above. Then force PostgreSQL to read the entire table.

Run a full table scan. The `count(*)` forces PostgreSQL to read every single row.

```sql
SELECT count(*) FROM pgbench_accounts;
```

Expected output (yours will differ based on the scale factor used in the backup-pitr lab):

```
  count
---------
 1000000
(1 row)
```

Now re-run the buffer cache query to see how the cached pages changed.

```sql
SELECT c.relname, count(*) AS buffers,
       pg_size_pretty(count(*) * 8192) AS cached_size
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = c.relfilenode
WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY c.relname
ORDER BY buffers DESC
LIMIT 10;
```

Expected output (yours will differ):

```
        relname        | buffers | cached_size
-----------------------+---------+-------------
 pgbench_accounts      |   16394 | 128 MB
 pgbench_accounts_pkey |    2745 | 21 MB
 pgbench_tellers       |       2 | 16 kB
 pgbench_branches      |       1 | 8192 bytes
(4 rows)
```

Compare the before and after. After the full table scan, `pgbench_accounts` should be occupying significantly more buffer space because PostgreSQL had to read all its pages into shared_buffers.

---

## 5. Cache Hit Ratio

**Run on NODE1 (pg-primary):**

The cache hit ratio tells you what percentage of page requests were satisfied from shared_buffers (a "hit") vs. having to read from disk (a "read"). This is one of the most important health metrics for any PostgreSQL server.

We are still connected to `labdb`. The `pg_stat_database` view is system-wide, so it works from any database - the `WHERE datname = current_database()` filter will show stats for `labdb`.

Run the following query against `pg_stat_database`.

```sql
SELECT datname,
       blks_hit,
       blks_read,
       CASE WHEN blks_hit + blks_read = 0 THEN 0
            ELSE round(blks_hit::numeric / (blks_hit + blks_read) * 100, 2)
       END AS hit_ratio_pct
FROM pg_stat_database
WHERE datname = current_database();
```

Expected output (yours will differ):

```
 datname | blks_hit | blks_read | hit_ratio_pct
---------+----------+-----------+---------------
 labdb   |   245831 |     19230 |         92.75
(1 row)
```

- `blks_hit` - number of times a page was found in shared_buffers (no disk read needed)
- `blks_read` - number of times a page had to be read from disk (or OS cache)
- `hit_ratio_pct` - the percentage of requests served from cache

In production, you want this above 99%. A low ratio means PostgreSQL is constantly going to disk, which is slow. The fix is usually to increase `shared_buffers` or to investigate queries that scan too much data.

> **Concept: Cache Hit Ratio Is Not the Whole Story**
> A 99%+ hit ratio is good, but it can be misleading. A `blks_read` that goes through the OS page cache is fast (microseconds), while a true disk read is slow (milliseconds). PostgreSQL counts both as `blks_read`. Also, a single bad query doing sequential scans can tank your ratio even if everything else is fine. Always pair this metric with actual I/O wait times.

---

## 6. Background Writer Stats

**Run on NODE1 (pg-primary):**

PostgreSQL has background processes that write dirty buffers (modified pages) from shared_buffers to disk. Understanding who is doing the writing helps you tune memory and checkpoint settings.

Query `pg_stat_bgwriter` to see the write activity.

```sql
SELECT checkpoints_timed, checkpoints_req,
       buffers_checkpoint, buffers_clean, buffers_backend
FROM pg_stat_bgwriter;
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | buffers_checkpoint | buffers_clean | buffers_backend
-------------------+-----------------+--------------------+---------------+-----------------
                12 |               3 |              24680 |           512 |             843
(1 row)
```

Here is what each column means:

- `checkpoints_timed` - checkpoints triggered on schedule (every `checkpoint_timeout` seconds). These are normal and expected.
- `checkpoints_req` - checkpoints forced because WAL filled up or an admin ran CHECKPOINT. Too many of these means your `max_wal_size` is too small.
- `buffers_checkpoint` - number of buffers written to disk during checkpoints. This is the bulk of the write work.
- `buffers_clean` - number of buffers written by the background writer process between checkpoints. This process slowly cleans dirty buffers so checkpoints have less work.
- `buffers_backend` - number of buffers written by regular backend processes themselves. This happens when a backend needs a buffer slot but all slots are dirty. If this number is high relative to the others, your `shared_buffers` may be too small or your background writer is not keeping up.

> **Concept: Who Writes Dirty Pages?**
> Three processes can write dirty pages to disk: the checkpointer (during scheduled or forced checkpoints), the background writer (continuously between checkpoints), and individual backends (as a last resort). You want the checkpointer and background writer to handle most writes. When backends have to write their own pages, they stall - the user query waits while the page is flushed to disk. High `buffers_backend` is a red flag.

---

## 7. Per-Backend Memory

**Run on NODE1 (pg-primary):**

Every time a client connects to PostgreSQL, a new backend process is forked. Each backend gets its own private memory allocation for sorting, hashing, and temporary tables. This memory is separate from shared_buffers.

Check the current `work_mem` setting.

```sql
SHOW work_mem;
```

Expected output:

```
 work_mem
----------
 4MB
(1 row)
```

This looks small, but here is the danger. `work_mem` is allocated per-operation, not per-connection. A single complex query with multiple sort and hash operations can allocate `work_mem` multiple times.

Consider this math:

- 100 connections
- Each running a query with 5 sort/hash operations
- work_mem = 4MB

That is 100 x 5 x 4MB = **2GB of memory** - just for sorting. This is on top of shared_buffers and everything else.

Let's see how many connections are active right now.

```sql
SELECT count(*) AS total_connections,
       count(*) FILTER (WHERE state = 'active') AS active
FROM pg_stat_activity
WHERE backend_type = 'client backend';
```

Expected output (yours will differ):

```
 total_connections | active
-------------------+--------
                 1 |      1
(1 row)
```

The `FILTER (WHERE state = 'active')` clause counts only backends currently running a query. This is the number you multiply by `work_mem` to estimate worst-case memory usage.

Now exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

**You are now ec2-user.**

---

## Checkpoint

Confirm you can do the following before moving on:

- [x] Can check all memory-related settings (shared_buffers, work_mem, maintenance_work_mem, effective_cache_size, wal_buffers)
- [x] Installed pg_buffercache and can inspect cached pages
- [x] Can calculate cache hit ratio from pg_stat_database
- [x] Understand the difference between shared memory and per-backend memory
- [x] Can read pg_stat_bgwriter output and know what each column means
- [x] Understand the work_mem multiplication danger (connections x operations x work_mem)

---

**Next:** [Build 03: Storage Architecture](03-storage-architecture.md)
