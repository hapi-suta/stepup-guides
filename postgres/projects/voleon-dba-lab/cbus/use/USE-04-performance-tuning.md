# USE Exercise 04: Performance Investigation

| | |
|---|---|
| **Time** | 40 minutes |
| **Server** | pg-primary (3.90.199.62) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Practice
- Enabling and querying pg_stat_statements
- Finding the top 10 queries by total execution time and by call count
- Identifying slow queries with high mean execution time
- Using EXPLAIN ANALYZE on a market_data query with partition pruning
- Using EXPLAIN ANALYZE on a signals query with and without an index
- Checking index usage stats to find unused indexes
- Checking table bloat using pg_stat_user_tables
- Running VACUUM ANALYZE on market_data
- Checking the cache hit ratio via pg_stat_database
- Identifying tables with high sequential scan counts (candidates for new indexes)

---

## Exercise 1: SSH into the primary

On your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

---

## Exercise 2: Connect to quantdb as postgres

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

---

## Exercise 3: Enable pg_stat_statements

pg_stat_statements tracks execution statistics for every query run against the database. Check if it is already enabled:

Still as **postgres** in the psql session on **pg-primary**:

```sql
SELECT name, setting FROM pg_settings WHERE name = 'shared_preload_libraries';
```

Expected output (yours will differ):
```
           name           |              setting
--------------------------+------------------------------------
 shared_preload_libraries | pg_stat_statements,pg_prewarm
(1 row)
```

Check if the extension is installed in quantdb:

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';
```

If no row is returned, create the extension:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Confirm the view is accessible:

```sql
SELECT COUNT(*) FROM pg_stat_statements;
```

---

## Exercise 4: Find the top 10 queries by total execution time

Still as **postgres** in the psql session on **pg-primary**:

This query shows which queries have consumed the most total CPU time across all their executions:

```sql
SELECT
  LEFT(query, 80) AS query_snippet,
  calls,
  round(total_exec_time::numeric, 2) AS total_ms,
  round(mean_exec_time::numeric, 2) AS mean_ms,
  round((100.0 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) AS pct_total
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):
```
               query_snippet                | calls | total_ms  | mean_ms | pct_total
-------------------------------------------+-------+-----------+---------+-----------
 SELECT md.symbol, md.price, md.volume ...  | 82341 | 412340.12 |    5.01 |     38.20
 INSERT INTO quant.market_data ...          | 14820 | 198200.00 |   13.37 |     18.36
 ...
```

The `pct_total` column tells you what percentage of all database time each query uses. Focus your optimization effort on queries at the top of this list.

---

## Exercise 5: Find the top 10 queries by call count

Still as **postgres** in the psql session on **pg-primary**:

High call counts with low mean time can still add up to significant load:

```sql
SELECT
  LEFT(query, 80) AS query_snippet,
  calls,
  round(mean_exec_time::numeric, 2) AS mean_ms,
  round(total_exec_time::numeric, 2) AS total_ms
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;
```

---

## Exercise 6: Identify slow queries (mean execution time over 100ms)

Still as **postgres** in the psql session on **pg-primary**:

Queries with a high mean execution time indicate something is wrong - missing index, table bloat, bad query plan, or locking:

```sql
SELECT
  LEFT(query, 100) AS query_snippet,
  calls,
  round(mean_exec_time::numeric, 2) AS mean_ms,
  round(max_exec_time::numeric, 2) AS max_ms,
  round(stddev_exec_time::numeric, 2) AS stddev_ms
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY mean_exec_time DESC
LIMIT 10;
```

Pay attention to the `stddev_ms` column - a high standard deviation means the query runs fast sometimes and slow other times, which usually points to locking or cache misses.

---

## Exercise 7: EXPLAIN ANALYZE on a market_data query with partition pruning

Still as **postgres** in the psql session on **pg-primary**:

market_data is partitioned (usually by date or symbol range). A well-written query should only scan the relevant partitions. First, run a query without any partition key in the WHERE clause to see a full scan:

```sql
EXPLAIN ANALYZE
SELECT symbol, price, volume
FROM quant.market_data
WHERE price > 500.00
LIMIT 100;
```

Look for lines that say `Seq Scan on market_data_*` in the output. Count how many partitions are scanned.

Now run the same query WITH a partition key to see pruning in action:

```sql
EXPLAIN ANALYZE
SELECT symbol, price, volume
FROM quant.market_data
WHERE trade_date >= '2026-01-01'
  AND trade_date < '2026-02-01'
  AND price > 500.00
LIMIT 100;
```

Expected output (yours will differ):
```
 Append  (cost=0.00..1234.56 rows=100 width=32) (actual time=0.123..4.567 rows=100 loops=1)
   ->  Seq Scan on market_data_2026_01  (cost=...) ...
 Planning Time: 1.234 ms
 Execution Time: 5.678 ms
```

With partition pruning, only the January 2026 partition is scanned instead of all partitions. This is the difference between a 5ms query and a 5-second query on large tables.

---

## Exercise 8: EXPLAIN ANALYZE on a signals query - with and without index

Still as **postgres** in the psql session on **pg-primary**:

First, check what indexes exist on the signals table:

```sql
\di quant.signals_*
```

Run EXPLAIN ANALYZE normally (with available indexes):

```sql
EXPLAIN ANALYZE
SELECT signal_id, model_id, symbol, signal_value, generated_at
FROM quant.signals
WHERE model_id = 5
  AND generated_at >= NOW() - INTERVAL '7 days'
ORDER BY generated_at DESC
LIMIT 50;
```

Look for `Index Scan` or `Bitmap Index Scan` in the output - this is fast.

Now force a sequential scan by disabling index usage for this session:

```sql
SET enable_indexscan = off;
SET enable_bitmapscan = off;
```

Run the same query again:

```sql
EXPLAIN ANALYZE
SELECT signal_id, model_id, symbol, signal_value, generated_at
FROM quant.signals
WHERE model_id = 5
  AND generated_at >= NOW() - INTERVAL '7 days'
ORDER BY generated_at DESC
LIMIT 50;
```

Expected output (yours will differ):
```
 Seq Scan on signals  (cost=0.00..98432.10 rows=50 width=48) (actual time=234.123..2341.567 rows=50 loops=1)
   Filter: ((model_id = 5) AND (generated_at >= ...))
   Rows Removed by Filter: 4829432
 Planning Time: 0.987 ms
 Execution Time: 2342.456 ms
```

The sequential scan is dramatically slower. Re-enable indexes before continuing:

```sql
SET enable_indexscan = on;
SET enable_bitmapscan = on;
```

---

## Exercise 9: Check index usage stats and find unused indexes

Still as **postgres** in the psql session on **pg-primary**:

Unused indexes waste disk space and slow down writes (every INSERT/UPDATE/DELETE must update every index on the table):

```sql
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan AS times_used,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname IN ('quant', 'ops')
  AND idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

Any index with `times_used = 0` has never been used since the last stats reset. Candidates for removal after confirming they are not needed for constraint enforcement.

Also check which indexes are used most:

```sql
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan AS times_used,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname IN ('quant', 'ops')
ORDER BY idx_scan DESC
LIMIT 10;
```

---

## Exercise 10: Check table bloat with pg_stat_user_tables

Still as **postgres** in the psql session on **pg-primary**:

Dead tuples are rows that have been deleted or updated but not yet physically removed. High dead tuple counts cause table bloat, which slows down sequential scans:

```sql
SELECT
  schemaname,
  relname AS tablename,
  n_live_tup AS live_rows,
  n_dead_tup AS dead_rows,
  CASE
    WHEN n_live_tup > 0
    THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
    ELSE 0
  END AS dead_pct,
  last_vacuum,
  last_autovacuum,
  last_analyze
FROM pg_stat_user_tables
WHERE schemaname IN ('quant', 'ops')
ORDER BY n_dead_tup DESC;
```

Expected output (yours will differ):
```
 schemaname |  tablename  | live_rows | dead_rows | dead_pct |       last_vacuum        | last_autovacuum
------------+-------------+-----------+-----------+----------+--------------------------+-------------------
 quant      | market_data | 9842310   | 124321    |     1.25 | 2026-06-14 02:00:01+00   | 2026-06-15 06:00:02
 quant      | signals     | 4829432   | 82341     |     1.67 | 2026-06-14 02:00:01+00   | ...
```

A `dead_pct` over 10-20% is a sign that autovacuum is not keeping up.

---

## Exercise 11: Run VACUUM ANALYZE on market_data

Still as **postgres** in the psql session on **pg-primary**:

VACUUM removes dead tuples. ANALYZE updates the query planner statistics. Running both together is common maintenance:

```sql
VACUUM ANALYZE quant.market_data;
```

This runs on all partitions of market_data. On a large table it may take a minute or more.

After it completes, check the dead tuple count again:

```sql
SELECT
  relname AS tablename,
  n_dead_tup AS dead_rows,
  last_vacuum,
  last_analyze
FROM pg_stat_user_tables
WHERE relname = 'market_data';
```

Expected output (yours will differ):
```
  tablename  | dead_rows |         last_vacuum          |         last_analyze
-------------+-----------+------------------------------+------------------------------
 market_data |         0 | 2026-06-15 14:58:00.123456+00 | 2026-06-15 14:58:01.234567+00
(1 row)
```

Dead rows should be 0 or very close to 0 after a manual VACUUM.

---

## Exercise 12: Check the cache hit ratio

Still as **postgres** in the psql session on **pg-primary**:

The cache hit ratio tells you how often PostgreSQL reads data from shared_buffers (RAM) vs. disk. A healthy OLTP database should be above 95%:

```sql
SELECT
  datname,
  blks_hit,
  blks_read,
  CASE
    WHEN (blks_hit + blks_read) > 0
    THEN round(100.0 * blks_hit / (blks_hit + blks_read), 2)
    ELSE 0
  END AS cache_hit_pct,
  xact_commit,
  xact_rollback,
  deadlocks
FROM pg_stat_database
WHERE datname = 'quantdb';
```

Expected output (yours will differ):
```
 datname | blks_hit | blks_read | cache_hit_pct | xact_commit | xact_rollback | deadlocks
---------+----------+-----------+---------------+-------------+---------------+-----------
 quantdb | 98432100 |   4821000 |         95.32 |     1482100 |           321 |         0
(1 row)
```

If `cache_hit_pct` is below 90%, the `shared_buffers` setting may need to be increased, or the working set is too large for available RAM.

Also check for deadlocks - a non-zero deadlock count needs investigation.

---

## Exercise 13: Identify tables with high sequential scan counts

Still as **postgres** in the psql session on **pg-primary**:

Tables with many sequential scans and large row counts are good candidates for new indexes. Sequential scans on small lookup tables are fine - they are fast. Sequential scans on million-row tables are a problem:

```sql
SELECT
  schemaname,
  relname AS tablename,
  seq_scan,
  seq_tup_read,
  idx_scan,
  n_live_tup AS live_rows,
  CASE
    WHEN seq_scan > 0
    THEN round(seq_tup_read::numeric / seq_scan, 0)
    ELSE 0
  END AS avg_rows_per_seq_scan
FROM pg_stat_user_tables
WHERE schemaname IN ('quant', 'ops')
  AND seq_scan > 10
ORDER BY seq_tup_read DESC
LIMIT 10;
```

Expected output (yours will differ):
```
 schemaname |  tablename  | seq_scan | seq_tup_read | idx_scan | live_rows | avg_rows_per_seq_scan
------------+-------------+----------+--------------+----------+-----------+----------------------
 quant      | market_data |      124 |  1219005360  |  9823410 |   9842310 |               9831494
 quant      | signals     |       87 |   420060840  |  4201230 |   4829432 |               4828285
```

A table where `avg_rows_per_seq_scan` is close to `live_rows` means almost the entire table is being read each time. If `seq_scan` is high for that table, a targeted index could eliminate most of that work.

---

## Exercise 14: Reset pg_stat_statements for a clean baseline

Still as **postgres** in the psql session on **pg-primary**:

After a performance investigation or tuning session, reset the stats to start fresh:

```sql
SELECT pg_stat_statements_reset();
```

Similarly, to reset table-level stats (use carefully - this clears last_vacuum and last_analyze timestamps too):

```sql
-- Only run this if you want a clean slate for testing.
-- Do NOT run this on a production server during business hours.
-- SELECT pg_stat_reset();
```

The pg_stat_statements reset is safe at any time. The pg_stat_reset command is left commented out as a reminder.

---

## Exercise 15: Exit cleanly

In the psql session:

```sql
\q
```

Exit the postgres shell:

```bash
exit
```

---

## Summary

In this exercise you:
- Enabled pg_stat_statements and queried it to find top queries by time and by call count
- Identified slow queries with mean_exec_time over 100ms
- Used EXPLAIN ANALYZE to see partition pruning on market_data queries
- Compared index scan vs. sequential scan performance on the signals table
- Found unused indexes that waste space and slow down writes
- Checked table bloat via dead tuple counts in pg_stat_user_tables
- Ran VACUUM ANALYZE on market_data and confirmed dead tuples were cleared
- Checked the cache hit ratio and identified any deadlocks
- Found tables with high sequential scan counts as candidates for new indexes
- Reset pg_stat_statements for a clean baseline
