# Build 05 - pg_stat_statements In Depth

**Time:** 40 minutes
**Goal:** Enable and configure pg_stat_statements, write the essential diagnostic queries, and integrate it into a routine performance review workflow.
**Prerequisites:** RDS PostgreSQL instance with a custom parameter group. psql access. `$DB_INSTANCE_ID` and `$REGION` set.

---

## Background

`pg_stat_statements` is a PostgreSQL extension that tracks execution statistics for every unique query type (normalized). It is the foundation of every PostgreSQL performance investigation. Performance Insights Top SQL is built on top of it.

The key insight: you cannot tune what you cannot measure. `pg_stat_statements` gives you exact numbers - how many times a query ran, how long it took in total, how much disk it read, how much temp space it used.

---

## Step 1 - Create a Custom Parameter Group (If You Don't Have One)

On RDS, you cannot modify the default parameter groups. You need a custom one.

Check if you already have a custom parameter group:

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].DBParameterGroups" \
  --output table \
  --region "$REGION"
```

Expected output (yours will differ):
```
----------------------------------------------
|           DescribeDBInstances              |
+---------------------------+----------------+
|  DBParameterGroupName     |  ParameterApplyStatus |
+---------------------------+----------------+
|  default.postgres16       |  in-sync        |
+---------------------------+----------------+
```

If you see `default.postgres16`, create a custom group:

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --db-parameter-group-family "postgres16" \
  --description "Custom PostgreSQL 16 parameter group for performance tuning" \
  --region "$REGION"
```

Each flag explained:
- `--db-parameter-group-family "postgres16"`: Must match your PostgreSQL major version.
- `--description`: A human-readable label. Shown in the console.

Attach it to your instance:

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --db-parameter-group-name "custom-pg16-perf" \
  --apply-immediately \
  --region "$REGION"
```

---

## Step 2 - Enable pg_stat_statements

Set the required parameters:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "custom-pg16-perf" \
  --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
    "ParameterName=pg_stat_statements.track,ParameterValue=all,ApplyMethod=immediate" \
    "ParameterName=pg_stat_statements.max,ParameterValue=10000,ApplyMethod=immediate" \
    "ParameterName=track_io_timing,ParameterValue=1,ApplyMethod=immediate" \
  --region "$REGION"
```

Each parameter explained:
- `shared_preload_libraries=pg_stat_statements`: Loads the extension at startup. Requires a reboot.
- `pg_stat_statements.track=all`: Track both top-level statements and statements called by functions. `top` tracks only direct client queries; `all` tracks everything.
- `pg_stat_statements.max=10000`: Maximum number of unique normalized queries to track. When this fills up, the least-used queries are evicted.
- `track_io_timing=1`: Enables timing of disk read and write operations. Adds a small overhead (typically <1%) but enables `blk_read_time` and `blk_write_time` columns.

`shared_preload_libraries` requires a reboot. Reboot the instance:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"
```

Wait for the instance to come back:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"
```

Expected output (yours will differ):
```
(no output - exits when instance is available)
```

---

## Step 3 - Create the Extension in Your Database

Connect to your database:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

Create the extension:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Verify it loaded:

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';
```

Expected output (yours will differ):
```
       extname        | extversion
----------------------+------------
 pg_stat_statements   | 1.10
```

---

## Step 4 - Generate Sample Query Load

Before running diagnostic queries, you need data. Generate some load:

```sql
-- Create test table
CREATE TABLE IF NOT EXISTS transactions (
    txn_id BIGSERIAL PRIMARY KEY,
    account_id INT NOT NULL,
    merchant_id INT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    currency CHAR(3) DEFAULT 'USD',
    txn_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_txn_account ON transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_txn_merchant ON transactions(merchant_id);

-- Insert 1M rows
INSERT INTO transactions (account_id, merchant_id, amount, txn_type, status)
SELECT
    (random() * 50000)::INT,
    (random() * 2000)::INT,
    (random() * 5000 + 1)::NUMERIC(12,2),
    CASE (random() * 3)::INT WHEN 0 THEN 'purchase' WHEN 1 THEN 'refund' ELSE 'transfer' END,
    CASE (random() * 4)::INT WHEN 0 THEN 'pending' WHEN 1 THEN 'cleared' WHEN 2 THEN 'failed' ELSE 'reversed' END
FROM generate_series(1, 1000000);

ANALYZE transactions;
```

Run a variety of query patterns:

```sql
-- Pattern 1: Point lookup (fast)
SELECT * FROM transactions WHERE account_id = 1234 AND status = 'pending' LIMIT 10;

-- Pattern 2: Range scan (moderate)
SELECT account_id, sum(amount) FROM transactions
WHERE created_at > now() - interval '7 days'
GROUP BY account_id
ORDER BY sum(amount) DESC
LIMIT 20;

-- Pattern 3: Cross-table join (heavier)
SELECT t1.account_id, count(*) AS txn_count, sum(t1.amount) AS total
FROM transactions t1
JOIN transactions t2 ON t1.account_id = t2.account_id
WHERE t1.status = 'cleared'
GROUP BY t1.account_id
HAVING count(*) > 5
LIMIT 50;

-- Pattern 4: Expensive aggregation without index
SELECT merchant_id, txn_type, count(*), avg(amount)
FROM transactions
GROUP BY merchant_id, txn_type;
```

Run each query 5-10 times so pg_stat_statements accumulates data.

---

## Step 5 - Top Queries by Total Execution Time

This is your first query during any performance review:

```sql
SELECT
    queryid,
    left(query, 100) AS query_snippet,
    calls,
    round(total_exec_time::numeric, 0) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms,
    round(((total_exec_time / sum(total_exec_time) OVER ()) * 100)::numeric, 1) AS pct_of_total
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):
```
 queryid | query_snippet                              | calls | total_ms | avg_ms  | stddev_ms | pct_of_total
---------+--------------------------------------------+-------+----------+---------+-----------+--------------
  281938 | SELECT merchant_id, txn_type, count(*), a  |     8 |  48293.0 | 6036.63 |    843.12 |        72.4
  391827 | SELECT t1.account_id, count(*) AS txn_cou  |    10 |   9841.0 |  984.10 |    102.34 |        14.7
  482910 | SELECT account_id, sum(amount) FROM transa |     6 |   4293.0 |  715.50 |     88.21 |         6.4
  ...
```

The aggregation query by merchant_id and txn_type consumes 72% of total execution time despite running only 8 times. This is where you start.

---

## Step 6 - Queries by Disk Reads

Find queries that most benefit from indexing:

```sql
SELECT
    left(query, 100) AS query_snippet,
    calls,
    shared_blks_read AS disk_reads,
    shared_blks_hit AS cache_hits,
    round(shared_blks_read::numeric / nullif(calls, 0), 0) AS disk_reads_per_call,
    round(
        shared_blks_hit::numeric /
        nullif(shared_blks_hit + shared_blks_read, 0) * 100,
        1
    ) AS cache_hit_pct
FROM pg_stat_statements
WHERE shared_blks_read > 1000
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY disk_reads_per_call DESC
LIMIT 10;
```

Queries with a low `cache_hit_pct` (below 90%) and high `disk_reads_per_call` are candidates for indexing or shared_buffers increase.

---

## Step 7 - Queries with Sort Spills

Find queries generating temp files (need more work_mem):

```sql
SELECT
    left(query, 100) AS query_snippet,
    calls,
    temp_blks_written,
    round(temp_blks_written::numeric / nullif(calls, 0), 0) AS temp_blks_per_call,
    round(mean_exec_time::numeric, 0) AS avg_ms
FROM pg_stat_statements
WHERE temp_blks_written > 0
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY temp_blks_written DESC
LIMIT 10;
```

Each block is 8KB. If `temp_blks_per_call` is 1000, the query spills 8MB per call to disk.

---

## Step 8 - Queries with High Execution Time Variance

Unstable query plans show up as high standard deviation relative to mean:

```sql
SELECT
    left(query, 100) AS query_snippet,
    calls,
    round(mean_exec_time::numeric, 0) AS avg_ms,
    round(stddev_exec_time::numeric, 0) AS stddev_ms,
    round((stddev_exec_time / nullif(mean_exec_time, 0) * 100)::numeric, 1) AS cv_pct,
    round(min_exec_time::numeric, 0) AS min_ms,
    round(max_exec_time::numeric, 0) AS max_ms
FROM pg_stat_statements
WHERE calls > 20
  AND mean_exec_time > 5
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY cv_pct DESC
LIMIT 10;
```

A coefficient of variation (`cv_pct`) above 50% indicates the query is sometimes fast and sometimes slow. This often means the planner chooses different plans based on parameter values (parameter sniffing problem). Fix: use Query Plan Management (Build 11) or pg_hint_plan.

---

## Step 9 - WAL Generation (Write-Heavy Queries)

Find queries generating the most WAL (write load on replicas and disk):

```sql
SELECT
    left(query, 100) AS query_snippet,
    calls,
    wal_bytes,
    wal_records,
    round(wal_bytes::numeric / nullif(calls, 0) / 1024, 1) AS wal_kb_per_call
FROM pg_stat_statements
WHERE wal_bytes > 0
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY wal_bytes DESC
LIMIT 10;
```

This column is available in PostgreSQL 13+. High WAL generation from a single query type means writes are concentrated - worth investigating if you are hitting WAL write bottlenecks.

---

## Step 10 - I/O Timing Breakdown

With `track_io_timing=on`, you can see how much of query time is spent waiting on disk I/O:

```sql
SELECT
    left(query, 100) AS query_snippet,
    calls,
    round(mean_exec_time::numeric, 2) AS avg_exec_ms,
    round((blk_read_time / nullif(calls, 0))::numeric, 2) AS avg_read_wait_ms,
    round((blk_write_time / nullif(calls, 0))::numeric, 2) AS avg_write_wait_ms,
    round(((blk_read_time + blk_write_time) / nullif(total_exec_time, 0) * 100)::numeric, 1) AS io_pct_of_time
FROM pg_stat_statements
WHERE (blk_read_time + blk_write_time) > 0
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY (blk_read_time + blk_write_time) DESC
LIMIT 10;
```

If `io_pct_of_time` is above 50%, the query is I/O bound. The fix is indexing, shared_buffers increase, or faster storage.

---

## Step 11 - Resetting Statistics

Reset all accumulated statistics at the start of a controlled performance test:

```sql
SELECT pg_stat_statements_reset();
```

Reset statistics for one specific query (PostgreSQL 14+):

```sql
-- Get the queryid first
SELECT queryid FROM pg_stat_statements WHERE query LIKE '%merchant_id%' LIMIT 1;

-- Then reset just that query
SELECT pg_stat_statements_reset(0, 0, 281938);  -- replace 281938 with actual queryid
```

`pg_stat_statements_reset(userid, dbid, queryid)`: Pass 0 for userid and dbid to match any user/database for that queryid.

---

## Step 12 - Automate a Weekly Performance Report

Create a function that generates a performance summary you can run weekly:

```sql
CREATE OR REPLACE FUNCTION generate_perf_report()
RETURNS TABLE(
    category TEXT,
    query_snippet TEXT,
    calls BIGINT,
    avg_ms NUMERIC,
    impact TEXT
) AS $$
BEGIN
    RETURN QUERY
    -- Top by total time
    SELECT
        'TOP_BY_TOTAL_TIME'::TEXT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        round((total_exec_time / sum(total_exec_time) OVER () * 100)::numeric, 1)::TEXT || '% of total'
    FROM pg_stat_statements s
    WHERE query NOT LIKE '%pg_stat_statements%'
    ORDER BY total_exec_time DESC
    LIMIT 5;

    RETURN QUERY
    -- Top by disk reads
    SELECT
        'TOP_DISK_READS'::TEXT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        round(shared_blks_read::numeric / nullif(s.calls, 0), 0)::TEXT || ' reads/call'
    FROM pg_stat_statements s
    WHERE shared_blks_read > 0
      AND query NOT LIKE '%pg_stat_statements%'
    ORDER BY shared_blks_read DESC
    LIMIT 5;

    RETURN QUERY
    -- Top temp file users
    SELECT
        'TOP_TEMP_FILES'::TEXT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        round(temp_blks_written::numeric / nullif(s.calls, 0) * 8, 0)::TEXT || ' KB/call spill'
    FROM pg_stat_statements s
    WHERE temp_blks_written > 0
      AND query NOT LIKE '%pg_stat_statements%'
    ORDER BY temp_blks_written DESC
    LIMIT 5;
END;
$$ LANGUAGE plpgsql;
```

Run the report:

```sql
SELECT * FROM generate_perf_report();
```

---

## Cleanup

```sql
DROP FUNCTION IF EXISTS generate_perf_report();
DROP TABLE IF EXISTS transactions;
SELECT pg_stat_statements_reset();
```

---

## Summary

You have:
- Enabled pg_stat_statements with track_io_timing for full visibility
- Written queries to find top consumers by time, disk reads, temp files, WAL, and I/O wait
- Identified plan instability via execution time variance
- Built an automated weekly performance report function

Run the diagnostic queries in Steps 5-10 as your first action whenever you get a "the database is slow" alert. They will point you directly to the offending query.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| pg_stat_statements | Extension that accumulates execution stats per unique normalized query |
| track_io_timing | Parameter that enables timing of disk reads/writes (small overhead) |
| queryid | Hash of the normalized query text - unique identifier per query type |
| shared_blks_read | Disk reads (buffer cache misses) - high value = needs index or more cache |
| temp_blks_written | Sort/hash spills to disk - high value = increase work_mem |
| stddev_exec_time | Standard deviation of execution time - high vs. mean = unstable plan |
| wal_bytes | Bytes of WAL generated - indicator of write load |
| Coefficient of Variation | stddev / mean * 100 - measures plan instability |
