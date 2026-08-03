# Build 04 - Slow Query Analysis

**Time:** 45 minutes
**Goal:** Configure slow query logging, enable pg_stat_statements, and use both to systematically find and analyze slow queries.
**Prerequisites:** Aurora PostgreSQL cluster `devops-lab-cluster` running. `$WRITER_INSTANCE`, `$REGION` set. psql access to the database.

---

## Step 1 - Check Your Current Parameter Group

Before changing parameters, identify which parameter group your instance uses:

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --query "DBInstances[0].DBParameterGroups[0].DBParameterGroupName" \
  --output text \
  --region "$REGION"
```

Expected output (yours will differ):
```
devops-lab-params
```

Save it:

```bash
export PARAM_GROUP="devops-lab-params"
```

If you are using a default parameter group (e.g., `default.aurora-postgresql16`), you need to create a custom one first because default groups cannot be modified:

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name "devops-lab-params" \
  --db-parameter-group-family "aurora-postgresql16" \
  --description "DevOps lab custom parameters" \
  --region "$REGION"
```

Then associate it with your instance:

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --db-parameter-group-name "devops-lab-params" \
  --apply-immediately \
  --region "$REGION"
```

---

## Step 2 - Enable Slow Query Logging

Configure PostgreSQL to log queries that take longer than a threshold:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP" \
  --parameters \
    "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate" \
    "ParameterName=log_statement,ParameterValue=none,ApplyMethod=immediate" \
  --region "$REGION"
```

Each parameter explained:
- `log_min_duration_statement=1000`: Log any statement that takes longer than 1000 milliseconds (1 second). Set to 0 to log all statements (very verbose - not recommended for production).
- `log_statement=none`: Do not log all statements separately. We only want the slow ones logged by `log_min_duration_statement`.

> **Concept:** `log_min_duration_statement` and `log_statement` are complementary but different. `log_statement` logs query text at submission time. `log_min_duration_statement` logs query text and duration at completion time. For performance analysis, you want `log_min_duration_statement` and can leave `log_statement` at `none`.

---

## Step 3 - Enable pg_stat_statements

pg_stat_statements is the most important PostgreSQL extension for performance work. It tracks execution statistics for every unique normalized query.

Check if it is already loaded:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name "$PARAM_GROUP" \
  --query "Parameters[?ParameterName=='shared_preload_libraries'].ParameterValue" \
  --output text \
  --region "$REGION"
```

If the output does not include `pg_stat_statements`, add it:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP" \
  --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
    "ParameterName=pg_stat_statements.track,ParameterValue=all,ApplyMethod=immediate" \
    "ParameterName=pg_stat_statements.max,ParameterValue=10000,ApplyMethod=immediate" \
    "ParameterName=track_io_timing,ParameterValue=on,ApplyMethod=immediate" \
  --region "$REGION"
```

Each parameter explained:
- `shared_preload_libraries=pg_stat_statements`: Load the extension at server startup. Requires a reboot.
- `pg_stat_statements.track=all`: Track both top-level and nested statements (inside functions/procedures).
- `pg_stat_statements.max=10000`: Maximum number of unique normalized queries to track. Default is 5000.
- `track_io_timing=on`: Enable timing of block read/write operations. This populates `blk_read_time` and `blk_write_time` in pg_stat_statements.

Reboot the instance (required for shared_preload_libraries change):

```bash
aws rds reboot-db-instance \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --region "$REGION"
```

Wait for it to come back:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --region "$REGION"
```

Now create the extension in your database:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Verify it is loaded:

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';
```

Expected output (yours will differ):
```
       extname       | extversion
---------------------+------------
 pg_stat_statements  | 1.10
```

---

## Step 4 - Understand pg_stat_statements Columns

The most important columns in pg_stat_statements:

| Column | What It Tells You |
|--------|------------------|
| query | Normalized query text (literals replaced with $1, $2, etc.) |
| calls | Total executions since last reset |
| total_exec_time | Total milliseconds spent executing |
| mean_exec_time | Average milliseconds per execution |
| stddev_exec_time | Standard deviation of execution time (high = unstable plans) |
| rows | Total rows returned |
| shared_blks_hit | Buffer cache hits (fast reads from RAM) |
| shared_blks_read | Disk reads (slow reads - cache misses) |
| shared_blks_dirtied | Pages modified (writes) |
| temp_blks_read | Temp file reads (sort/hash spills to disk) |
| temp_blks_written | Temp file writes (sort/hash spills to disk) |
| blk_read_time | Time waiting on disk reads (requires track_io_timing=on) |
| blk_write_time | Time waiting on disk writes |
| wal_bytes | WAL generated (amount of write activity) |

---

## Step 5 - Find the Top 10 Queries by Total Time

This is your primary query for performance investigations:

```sql
SELECT
    queryid,
    left(query, 80) AS query_snippet,
    calls,
    round(total_exec_time::numeric / 1000, 1) AS total_seconds,
    round(mean_exec_time::numeric, 1) AS avg_ms,
    round(stddev_exec_time::numeric, 1) AS stddev_ms,
    rows
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):
```
  queryid   |                         query_snippet                         | calls | total_seconds | avg_ms | stddev_ms |  rows
------------+---------------------------------------------------------------+-------+---------------+--------+-----------+--------
 1234567890 | SELECT count(*), status FROM perf_test WHERE amount > $1 GRO  |   150 |          12.5 |   83.3 |      15.2 |    450
 2345678901 | INSERT INTO perf_test (user_id, amount, status) SELECT ...    |     1 |           8.2 | 8200.0 |       0.0 | 500000
 ...
```

---

## Step 6 - Find Queries with the Most Disk Reads

These queries benefit most from indexing:

```sql
SELECT
    queryid,
    left(query, 80) AS query_snippet,
    calls,
    shared_blks_read,
    shared_blks_hit,
    round(shared_blks_read::numeric / nullif(calls, 0), 1) AS reads_per_call,
    round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 1) AS hit_ratio
FROM pg_stat_statements
WHERE shared_blks_read > 0
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY shared_blks_read DESC
LIMIT 10;
```

Expected output (yours will differ):
```
  queryid   |                   query_snippet                    | calls | shared_blks_read | shared_blks_hit | reads_per_call | hit_ratio
------------+----------------------------------------------------+-------+------------------+-----------------+----------------+-----------
 1234567890 | SELECT count(*), status FROM perf_test WHERE ...   |   150 |            45000 |           12000 |          300.0 |      21.1
```

A low `hit_ratio` per query means that query consistently misses the cache. It is a candidate for an index.

---

## Step 7 - Find Queries Spilling to Temp Files

These queries need more work_mem or query optimization:

```sql
SELECT
    queryid,
    left(query, 80) AS query_snippet,
    calls,
    temp_blks_written,
    round(temp_blks_written::numeric * 8 / 1024 / nullif(calls, 0), 1) AS temp_mb_per_call,
    round(mean_exec_time::numeric, 1) AS avg_ms
FROM pg_stat_statements
WHERE temp_blks_written > 0
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY temp_blks_written DESC
LIMIT 10;
```

`temp_blks_written * 8 / 1024`: Each block is 8 KB. This converts to MB.

---

## Step 8 - Find Queries with Unstable Execution Times

A high coefficient of variation (stddev / mean) suggests the query planner is choosing different plans:

```sql
SELECT
    queryid,
    left(query, 80) AS query_snippet,
    calls,
    round(mean_exec_time::numeric, 1) AS avg_ms,
    round(stddev_exec_time::numeric, 1) AS stddev_ms,
    round(stddev_exec_time / nullif(mean_exec_time, 0) * 100, 1) AS cv_pct
FROM pg_stat_statements
WHERE calls > 50
  AND mean_exec_time > 10
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY cv_pct DESC
LIMIT 10;
```

A `cv_pct` above 100% means the standard deviation exceeds the mean - the query sometimes runs much faster or slower than average. This often indicates plan instability or data skew.

---

## Step 9 - View Slow Query Logs

Check if slow queries are being logged to CloudWatch Logs:

```bash
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/rds/cluster/$CLUSTER_ID/postgresql" \
  --region "$REGION" \
  --query "logGroups[].logGroupName" \
  --output text
```

Expected output (yours will differ):
```
/aws/rds/cluster/devops-lab-cluster/postgresql
```

Search for slow query log entries:

```bash
aws logs filter-log-events \
  --log-group-name "/aws/rds/cluster/$CLUSTER_ID/postgresql" \
  --filter-pattern "duration" \
  --limit 5 \
  --region "$REGION" \
  --query "events[].message" \
  --output text
```

`--filter-pattern "duration"`: Matches log entries that contain the word "duration" - which is how PostgreSQL logs slow queries.

Expected output (yours will differ):
```
2026-06-09 14:30:15 UTC:10.0.1.50(52342):postgres@mydb:[1234]:LOG:  duration: 1523.456 ms  statement: SELECT count(*), status FROM perf_test WHERE amount > 500 GROUP BY status ORDER BY count(*) DESC
```

---

## Step 10 - Reset pg_stat_statements

Before starting a performance investigation, reset the statistics so you start with a clean baseline:

```sql
SELECT pg_stat_statements_reset();
```

Expected output:
```
 pg_stat_statements_reset
--------------------------

(1 row)
```

After the investigation, you can compare the new statistics against the clean baseline. This is especially useful when testing a fix: reset, run the workload, check the stats.

---

## Summary

You have:
- Configured slow query logging with log_min_duration_statement
- Enabled pg_stat_statements with track_io_timing
- Learned to find top queries by total time, disk reads, temp spills, and plan instability
- Viewed slow query logs in CloudWatch Logs
- Learned when and how to reset statistics

pg_stat_statements is the foundation of all query performance work. Use it before and after every optimization to measure improvement.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| log_min_duration_statement | Log queries exceeding this duration (milliseconds) |
| pg_stat_statements | Extension tracking execution statistics for all normalized queries |
| shared_preload_libraries | PostgreSQL parameter specifying extensions loaded at server startup |
| track_io_timing | Enables timing of block I/O operations for pg_stat_statements |
| Normalized query | Query with literal values replaced by $1, $2, etc. |
| shared_blks_hit | Number of times a needed page was found in shared_buffers (fast) |
| shared_blks_read | Number of times a needed page was read from storage (slow) |
| temp_blks_written | Number of temp file blocks written (sort/hash spill) |
| Coefficient of variation | stddev / mean * 100 - measures execution time consistency |
