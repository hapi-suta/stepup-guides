# Scenario 03 - work_mem Too Low

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Reports and ORDER BY queries are extremely slow.
Disk usage on /tmp is spiking.
Sort operations are taking 10x longer than expected.
```

---

## Key Concepts for Revision

- **work_mem is per sort/hash operation** - When PostgreSQL sorts rows (ORDER BY, DISTINCT, merge joins) or builds hash tables (hash joins, hash aggregates), it uses up to `work_mem` bytes of private memory. If the data exceeds `work_mem`, PostgreSQL writes sorted runs to temporary files on disk and merges them. This is called a "disk sort" or "external merge" and is 10-100x slower than an in-memory sort.

- **64kB is the absolute minimum** - PostgreSQL allows `work_mem = 64kB` but this is effectively unusable for any real query. A single page of data in PostgreSQL is 8kB. 64kB = 8 pages. Even a small ORDER BY on a table with 50 rows will spill to disk at 64kB.

- **Detecting spills in EXPLAIN** - `EXPLAIN (ANALYZE)` shows `Sort Method: external merge Disk: NkB` when a sort spilled to disk. `Sort Method: quicksort Memory: NkB` means it stayed in memory. `Sort Method: top-N heapsort Memory: NkB` means it used a heap for a LIMIT clause.

- **Detecting spills in pg_stat_database** - The `temp_files` and `temp_bytes` columns in `pg_stat_database` accumulate the count and size of all temporary files created since the last stats reset. High values confirm spills are happening.

- **ALTER SYSTEM vs postgresql.conf** - `ALTER SYSTEM SET work_mem = '64kB'` writes to `postgresql.auto.conf`. This file overrides `postgresql.conf`. To fix it, use `ALTER SYSTEM RESET work_mem` or `ALTER SYSTEM SET work_mem = 'correct_value'`. Do NOT edit `postgresql.auto.conf` directly.

---

## Diagnostic Steps

### Step 1 - Check current work_mem

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW work_mem;"
```

Expected output:

```
 work_mem
----------
 64kB
(1 row)
```

64kB confirms the problem.

### Step 2 - Check for temp file spills in pg_stat_database

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT datname, temp_files, pg_size_pretty(temp_bytes) AS temp_size FROM pg_stat_database WHERE datname = 'stepup_store';"
```

Expected output (yours will differ):

```
   datname    | temp_files | temp_size
--------------+------------+-----------
 stepup_store |         42 | 18 MB
(1 row)
```

42 temp files and 18MB of temp data is a strong signal of sort spills.

### Step 3 - Confirm spill in an actual query plan

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "EXPLAIN ANALYZE SELECT customer_id, SUM(total_amount) FROM orders GROUP BY customer_id ORDER BY SUM(total_amount) DESC;"
```

Expected output (yours will differ):

```
 Sort  (cost=...) (actual time=... rows=50 loops=1)
   Sort Key: (sum(total_amount)) DESC
   Sort Method: external merge  Disk: 64kB
   ...
```

`external merge Disk:` confirms the sort spilled.

### Step 4 - Check postgresql.auto.conf for the bad value

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT sourcefile, setting FROM pg_settings WHERE name = 'work_mem';"
```

Expected output (yours will differ):

```
            sourcefile            | setting
----------------------------------+---------
 /opt/pgsql/data/postgresql.auto.conf | 64
(1 row)
```

The setting came from `postgresql.auto.conf` (written by ALTER SYSTEM).

---

## Resolution

### Step 1 - Reset work_mem to a sensible value

Do NOT edit `postgresql.auto.conf` directly. Use ALTER SYSTEM to override it.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET work_mem = '8MB';"
```

Expected output:

```
ALTER SYSTEM
```

### Step 2 - Reload configuration

A reload is sufficient for work_mem (no restart needed).

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 3 - Verify the new value

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW work_mem;"
```

Expected output:

```
 work_mem
----------
 8MB
(1 row)
```

### Step 4 - Confirm sorts no longer spill

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "EXPLAIN ANALYZE SELECT customer_id, SUM(total_amount) FROM orders GROUP BY customer_id ORDER BY SUM(total_amount) DESC;"
```

Expected output (yours will differ):

```
 Sort Method: quicksort  Memory: 27kB
```

`quicksort` and `Memory:` (not `Disk:`) confirms the sort is in memory now.

```bash
exit
```

---

## Validation

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- work_mem is at least 4MB
- Sort operation uses memory not disk
- temp_file_limit is not blocking queries
- postgresql.auto.conf no longer contains 64kB work_mem

---

## Interview Discussion Points

1. **How do you find which queries are generating temp files in production?** - Enable `log_temp_files = 0` in postgresql.conf (logs all temp files) or set it to a size threshold like `log_temp_files = 10MB` (logs only spills larger than 10MB). Also query `pg_stat_database` for `temp_files` and `temp_bytes`. With pg_stat_statements enabled, the `temp_blks_written` column shows per-query temp file usage.

2. **Can raising work_mem cause problems?** - Yes. work_mem is per sort operation, not per session. A single complex query may run 5 sort/hash operations simultaneously, each using up to work_mem. With 50 sessions each running such queries, you could need 50 * 5 * work_mem = 250x work_mem bytes of RAM. On a 1GB server with 8MB work_mem, that is 2GB - enough to trigger OOM. Set work_mem conservatively globally and raise it per-session for heavy batch jobs.

3. **What is the difference between work_mem and temp_buffers?** - `work_mem` is for sort and hash operations on regular heap data. `temp_buffers` is the page cache for temporary tables created with `CREATE TEMP TABLE`. They are separate memory pools. A session doing heavy ETL might need both raised: `temp_buffers` for large temp tables and `work_mem` for sorting data from those temp tables.

4. **How do you identify the right value for work_mem on a production system?** - Start conservative (4-8MB). Enable `log_temp_files = 1MB`. After a week, look at which queries are logging temp files. Check `EXPLAIN ANALYZE` on those queries to see the actual sort sizes. Set work_mem to slightly above the largest common sort size. Then re-check memory pressure with `pg_stat_activity` during peak load.

5. **Does work_mem affect hash joins the same way as sorts?** - Yes. Hash joins build a hash table in memory. If the hash table exceeds work_mem, PostgreSQL splits it into batches and processes them with repeated passes over the data. This is called "batch processing" and shows in EXPLAIN as `Batches: N` where N > 1. One batch = in memory. Multiple batches = spilling to disk.
