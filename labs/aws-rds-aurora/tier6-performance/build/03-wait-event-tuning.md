# Build 03 - Tuning with Wait Events

**Time:** 45 minutes
**Goal:** Systematically diagnose and resolve performance problems using wait events from Performance Insights and pg_stat_activity. Simulate four real wait event scenarios and fix each one.
**Prerequisites:** Build 02 complete. psql access to the database. pg_stat_statements loaded.

---

## Background

Wait events are the single most accurate signal for diagnosing database performance problems. Every time a PostgreSQL session is not executing on CPU, it is waiting on something. That "something" is the wait event. When you see a pattern in wait events, you know exactly where to start tuning.

This guide walks you through four scenarios: IO reads (cache misses), lock contention, sort spills (work_mem), and high CPU (missing indexes). Each scenario has an inject section, a diagnosis section, and a fix section.

---

## Viewing Wait Events in Performance Insights (Console)

Before diving into the command line, you should know how to read wait events directly from the AWS Console. Performance Insights gives you a live visual of where your database is spending time. Use this as your first stop whenever performance is slow.

### Step 1 - Open Performance Insights for Your Instance

1. Go to the AWS Console and sign in.
2. In the top search bar, type **RDS** and click **RDS** in the results.
3. In the left sidebar, click **Databases**.
4. Find your Aurora cluster in the list and click its identifier (the blue link).
5. On the cluster detail page, look at the tabs near the top. Click the **Monitoring** tab.
6. Scroll down until you see a button labeled **View in Performance Insights** (it appears on the right side of the Monitoring tab). Click it.

You are now inside the **Performance Insights** dashboard for your database instance.

---

### Step 2 - Read the Database Load Chart

The first thing you see is a large chart at the top called **Database load**. This is the most important chart on the page.

- The **horizontal axis** is time (last 1 hour by default).
- The **vertical axis** is AAS (Average Active Sessions) - the average number of sessions doing work or waiting at any given second.
- The horizontal line labeled **Max vCPU** shows your instance's CPU ceiling. When the colored bars rise above that line, your database is overloaded.
- The colored bands stacked inside the bars represent wait events. Each color is a different category of wait.

The chart answers the question: "What is my database waiting on, and when did it start?"

---

### Step 3 - Slice the Chart by Wait Events

By default, the chart may be grouped by SQL or by host. You want to group it by wait events.

1. Look for the **Slice by** dropdown just above the **Database load** chart. It is on the right side of the chart header row.
2. Click the **Slice by** dropdown.
3. Select **Wait** from the list.

The chart now shows colored segments grouped by wait event category (IO, Lock, CPU, etc.). Each color represents a different type of wait.

---

### Step 4 - Identify Your Top Wait Events

Below the **Database load** chart is a legend table. It lists every wait event currently active, sorted by the amount of load they contribute.

Read the table from top to bottom:

- The **first row** is your dominant wait event - the one causing the most sessions to stall.
- The **Wait event** column shows the name (for example, `IO:DataFileRead`, `Lock:relation`, or `IO:BufFileWrite`).
- The **DB load** column shows the average number of sessions waiting on that event.

The top 1-3 rows tell you where to focus your tuning effort. If `IO:DataFileRead` is at the top, your queries are reading from disk. If `Lock:relation` is at the top, something is holding a lock and blocking others.

---

### Step 5 - Correlate Wait Events to Specific Queries Using Top SQL

Knowing the wait event is not enough. You also need to know which SQL statement is causing it.

1. Scroll down below the **Database load** chart.
2. You will see a section titled **Top SQL**. Click the **Top SQL** tab if it is not already selected.
3. The table lists your most active SQL statements ranked by **DB load** (how many sessions were running that statement on average).
4. Each row shows the query text (truncated), the **DB load** bar, and a breakdown of which wait events that specific query contributes to.
5. Click on any row to expand it. The expanded view shows the full query text and a per-wait-event breakdown for that statement.

Use this to answer: "Which query is causing most of my `IO:DataFileRead`?" - find `IO:DataFileRead` as the dominant wait in the legend, then look at the **Top SQL** table. The top rows are the queries driving that wait.

---

### What to Do with This Information

Once you have identified the top wait event and the query causing it, use the scenarios below to diagnose and fix it:

| What you see in PI | Scenario in this guide |
|--------------------|------------------------|
| `IO:DataFileRead` dominant | Scenario 1 |
| `Lock:relation` dominant | Scenario 2 |
| `IO:BufFileRead` or `IO:BufFileWrite` dominant | Scenario 3 |
| No clear wait event, CPU usage is high | Scenario 4 |

---

## Setup - Create Test Tables

Connect to your database:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

Create the tables you will use across all scenarios:

```sql
-- Large orders table (simulates a real-world e-commerce table)
CREATE TABLE IF NOT EXISTS orders (
    order_id BIGSERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    product_id INT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    region TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Insert 2 million rows
INSERT INTO orders (customer_id, product_id, amount, status, region)
SELECT
    (random() * 100000)::INT,
    (random() * 5000)::INT,
    (random() * 999.99 + 0.01)::NUMERIC(12,2),
    CASE (random() * 4)::INT
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'processing'
        WHEN 2 THEN 'shipped'
        ELSE 'completed'
    END,
    CASE (random() * 4)::INT
        WHEN 0 THEN 'us-east'
        WHEN 1 THEN 'us-west'
        WHEN 2 THEN 'eu-west'
        ELSE 'ap-south'
    END
FROM generate_series(1, 2000000);

ANALYZE orders;
```

This will take 1-2 minutes.

---

## Scenario 1 - IO:DataFileRead (Buffer Cache Misses)

### What It Looks Like in PI

When `IO:DataFileRead` dominates the DB Load chart, your queries are reading data from disk because it is not in shared_buffers. This is the most common wait event on databases smaller than their working set.

### Inject the Problem

Flush the buffer cache (simulates a cold start or a large sequential scan evicting hot pages):

```sql
-- Discard the buffer pool contents
-- This requires superuser and is safe on RDS
SELECT pg_prewarm('orders', 'buffer');
-- Wait - pg_prewarm actually warms the cache. Let's flush it differently.
-- Run a large sequential scan that fills the cache with orders data
-- then immediately query a different large table to evict it.
-- For this lab we just run the scan and watch PI.

-- Run a sequential scan (no index on customer_id yet)
SELECT count(*), avg(amount)
FROM orders
WHERE customer_id = 42;
```

Run this in a loop from another terminal to generate sustained IO:DataFileRead:

```bash
for i in $(seq 1 20); do
  CUSTID=$((RANDOM % 100000))
  psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT count(*), avg(amount) FROM orders WHERE customer_id = $CUSTID;" &
done
wait
```

### Diagnose

While the load is running, check what sessions are waiting on:

```sql
SELECT
    wait_event_type,
    wait_event,
    count(*) AS sessions,
    left(query, 60) AS query_sample
FROM pg_stat_activity
WHERE state = 'active'
  AND wait_event IS NOT NULL
GROUP BY 1, 2, 4
ORDER BY sessions DESC;
```

Expected output (yours will differ):
```
 wait_event_type | wait_event   | sessions | query_sample
-----------------+--------------+----------+----------------------------------
 IO              | DataFileRead |       12 | SELECT count(*), avg(amount)...
```

Check the table's I/O statistics:

```sql
SELECT
    relname,
    heap_blks_read AS disk_reads,
    heap_blks_hit AS cache_hits,
    round(heap_blks_hit::numeric / nullif(heap_blks_hit + heap_blks_read, 0) * 100, 2) AS hit_ratio
FROM pg_statio_user_tables
WHERE relname = 'orders';
```

A hit_ratio below 95% means the working set is not fitting in cache.

### Fix - Add an Index

```sql
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);
```

`CONCURRENTLY`: Builds the index without locking the table. It takes longer but does not block writes.

After the index is built, run the same query:

```sql
SELECT count(*), avg(amount)
FROM orders
WHERE customer_id = 42;
```

Expected output (yours will differ):
```
 count |        avg
-------+--------------------
    19 | 542.1589473684210526
```

Check the query plan to confirm index use:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), avg(amount)
FROM orders
WHERE customer_id = 42;
```

Expected output (yours will differ):
```
 Index Scan using idx_orders_customer_id on orders  (cost=0.56..74.5 rows=20 width=6) (actual time=0.142..0.892 rows=19 loops=1)
   Index Cond: (customer_id = 42)
   Buffers: shared hit=22
```

`Buffers: shared hit=22` means 22 buffer cache hits and 0 disk reads. The `IO:DataFileRead` wait event disappears.

---

## Scenario 2 - Lock:relation (Table Lock Contention)

### What It Looks Like in PI

`Lock:relation` appears when sessions are blocked waiting for table-level locks. Common causes: `VACUUM FULL`, `ALTER TABLE`, `TRUNCATE`, and some index operations.

### Inject the Problem

Open two psql sessions.

**Session A** - hold a lock:

```sql
BEGIN;
LOCK TABLE orders IN SHARE UPDATE EXCLUSIVE MODE;
-- Do NOT commit yet. Leave this session open.
SELECT pg_sleep(60);
```

**Session B** - try to write:

```sql
UPDATE orders SET status = 'processing' WHERE order_id = 1;
```

Session B hangs.

**Session C** - open a third session and check:

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.query AS blocking_query,
    now() - blocked.query_start AS blocked_for
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

Expected output (yours will differ):
```
 blocked_pid | blocked_query                      | blocking_pid | blocking_query  | blocked_for
-------------+------------------------------------+--------------+-----------------+-------------
        3421 | UPDATE orders SET status = '...'   |         3198 | SELECT pg_sleep | 00:00:12.34
```

### Fix - Identify and Kill the Blocking Session

```sql
-- Get the blocking PID from the query above
-- Then terminate it
SELECT pg_terminate_backend(3198);
```

For production: set `lock_timeout` so applications fail fast instead of hanging indefinitely:

```sql
-- Per-session
SET lock_timeout = '5s';

-- Or in parameter group for all sessions
-- lock_timeout = 5000 (milliseconds)
```

### Clean Up Session A

Go back to Session A and roll back:

```sql
ROLLBACK;
```

---

## Scenario 3 - IO:BufFileRead (work_mem Spills)

### What It Looks Like in PI

`IO:BufFileRead` and `IO:BufFileWrite` appear when sort or hash operations exceed work_mem and spill to disk temporary files. These are much slower than in-memory sorts.

### Inject the Problem

First, set work_mem very low to force spills:

```sql
SET work_mem = '64kB';
```

Now run a large sort:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, sum(amount) AS total
FROM orders
GROUP BY customer_id
ORDER BY total DESC
LIMIT 100;
```

Expected output (yours will differ):
```
 Sort  (cost=389201.49..390451.49 rows=500000 width=36) (actual time=4821.3..4832.1 rows=100 loops=1)
   Sort Key: (sum(amount)) DESC
   Sort Method: external merge  Disk: 8240kB
   ...
```

`Sort Method: external merge  Disk: 8240kB` - this is the spill. The sort used 8.2MB of temp files because work_mem was only 64kB.

Check for temp file usage in pg_stat_statements:

```sql
SELECT
    left(query, 80) AS query_snippet,
    temp_blks_written,
    calls,
    round(mean_exec_time::numeric, 0) AS avg_ms
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 5;
```

### Fix - Increase work_mem

```sql
SET work_mem = '256MB';
```

Run the same query again:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, sum(amount) AS total
FROM orders
GROUP BY customer_id
ORDER BY total DESC
LIMIT 100;
```

Expected output (yours will differ):
```
 Sort  (cost=389201.49..390451.49 rows=500000 width=36) (actual time=1203.4..1204.1 rows=100 loops=1)
   Sort Key: (sum(amount)) DESC
   Sort Method: quicksort  Memory: 25kB
   ...
```

`Sort Method: quicksort  Memory: 25kB` - the sort is now in memory. The `IO:BufFileRead` wait event disappears and query time drops significantly.

**Important:** Increase work_mem globally only after calculating the safe value. For session-specific large queries, use `SET work_mem = '256MB'` per session rather than changing the global default.

---

## Scenario 4 - CPU (Sequential Scans, Missing Indexes)

### What It Looks Like in PI

High CPU with no dominant lock or IO wait event usually means sessions are doing lots of computation: full table scans, complex regex operations, heavy aggregations. The fix is almost always an index or a query rewrite.

### Inject the Problem

```sql
-- Reset work_mem to a normal value first
RESET work_mem;

-- Pattern-matching query with no index support
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, amount
FROM orders
WHERE status LIKE '%process%'
  AND region = 'us-east';
```

Expected output (yours will differ):
```
 Seq Scan on orders  (cost=0.00..52831.00 rows=2500 width=28) (actual time=0.042..1432.1 rows=250241 loops=1)
   Filter: ((status ~~ '%process%') AND (region = 'us-east'))
   Rows Removed by Filter: 1749759
   Buffers: shared hit=17831
```

`Seq Scan on orders` scanning 2M rows, removing 1.75M. This saturates CPU.

### Diagnose Which Queries Are Using Most CPU

```sql
SELECT
    left(query, 80) AS query_snippet,
    calls,
    round(total_exec_time::numeric, 0) AS total_ms,
    round(mean_exec_time::numeric, 0) AS avg_ms,
    round((total_exec_time / sum(total_exec_time) OVER ()) * 100, 1) AS pct_of_total
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

### Fix Option 1 - Partial Index

The query has two filters. Create an index that covers the common constant filter:

```sql
CREATE INDEX CONCURRENTLY idx_orders_region_status
ON orders(region, status);
```

Check the plan:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, amount
FROM orders
WHERE status = 'processing'
  AND region = 'us-east';
```

Expected output (yours will differ):
```
 Bitmap Heap Scan on orders  (cost=1204.11..14832.44 rows=50012 width=28) (actual time=8.4..48.2 rows=49831 loops=1)
   Recheck Cond: ((region = 'us-east') AND (status = 'processing'))
   Buffers: shared hit=392 read=48
   ->  Bitmap Index Scan on idx_orders_region_status  (cost=0.00..1191.59 rows=50012 width=0) (actual time=7.2..7.2 rows=49831 loops=1)
```

Query went from 1432ms to 48ms. CPU drops substantially.

### Fix Option 2 - Rewrite the Query

The `LIKE '%process%'` pattern is not index-friendly (leading wildcard). Rewrite to use an equality check:

```sql
-- Instead of LIKE '%process%', use an equality match
SELECT order_id, customer_id, amount
FROM orders
WHERE status = 'processing'
  AND region = 'us-east';
```

---

## Scenario Comparison Summary

| Wait Event | Root Cause | Diagnostic Query | Fix |
|------------|-----------|-----------------|-----|
| IO:DataFileRead | Missing index, cold cache | pg_statio_user_tables hit_ratio | Add index, increase shared_buffers |
| Lock:relation | DDL or explicit lock blocking DML | pg_stat_activity + pg_blocking_pids | Kill blocking session, use lock_timeout |
| IO:BufFileRead | work_mem too low for sort/hash | pg_stat_statements temp_blks_written | Increase work_mem |
| CPU (no wait) | Sequential scans, missing indexes | pg_stat_statements total_exec_time | Add index, rewrite query |

---

## Cleanup

```sql
DROP INDEX IF EXISTS idx_orders_customer_id;
DROP INDEX IF EXISTS idx_orders_region_status;
DROP TABLE IF EXISTS orders;
RESET work_mem;
```

---

## Summary

You have:
- Diagnosed and resolved IO:DataFileRead with an index
- Identified and killed a blocking session causing Lock:relation
- Fixed work_mem spills causing IO:BufFileRead
- Added indexes to eliminate high-CPU sequential scans

The pattern is always: find the dominant wait event in Performance Insights, query pg_stat_activity or pg_stat_statements to identify the query, then apply the appropriate fix.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| IO:DataFileRead | Session reading a page from disk (not in shared_buffers) |
| Lock:relation | Session waiting for a table-level lock held by another session |
| IO:BufFileRead | Session reading from a temp file because sort/hash exceeded work_mem |
| pg_blocking_pids | PostgreSQL function that returns PIDs blocking a given session |
| CONCURRENTLY | Index build option that does not lock the table for writes |
| external merge | Sort method used when sort data exceeds work_mem (spills to disk) |
