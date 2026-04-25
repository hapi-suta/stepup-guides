# Build 12 - Parallel Query

**Estimated time:** 20-25 minutes

PostgreSQL can split large queries across multiple CPU cores. Instead of one process scanning an entire table, PostgreSQL launches worker processes that each scan a portion of the table, then combines the results. In this lab, you will see parallel query in action, measure the speedup, and learn when it helps and when it does not.

---

## Prerequisites

- SSH access to your lab server
- PostgreSQL 16 running at `/opt/pgsql/data`
- Database `labdb` created from a previous lab

---

## Section 1: How Parallel Query Works

When PostgreSQL decides a query is large enough to benefit from parallelism, it creates a plan like this:

```
                    +------------------+
                    |     Gather       |
                    | (combines results)|
                    +--------+---------+
                             |
              +--------------+--------------+
              |              |              |
     +--------+--+   +------+----+   +-----+-----+
     |  Worker 1  |   |  Worker 2  |   |  Leader   |
     | (scans     |   | (scans     |   | (scans    |
     |  rows 1-   |   |  rows      |   |  remaining|
     |  333,333)  |   |  333,334-  |   |  rows)    |
     |            |   |  666,666)  |   |           |
     +------------+   +------------+   +-----------+
```

The **Gather** node at the top launches worker processes. Each worker scans a portion of the table in parallel. The leader process also does some scanning. The Gather node collects all the results and passes them up to the rest of the query plan.

### Step 1: Log into your server

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@YOUR_SERVER_IP
```

### Step 2: Switch to the postgres user

```bash
sudo su - postgres
```

### Step 3: Connect to labdb

```bash
/usr/pgsql-16/bin/psql -d labdb
```

### Step 4: Check current parallel query settings

These four settings control parallel query behavior. Run each SHOW command to see the current values.

```sql
SHOW max_parallel_workers;
```

This is the total number of parallel worker processes allowed across all queries. Default is 8.

```sql
SHOW max_parallel_workers_per_gather;
```

This is the maximum number of workers a single query can use. Default is 2.

```sql
SHOW max_worker_processes;
```

This is the total number of background worker processes (includes parallel workers plus others like autovacuum). Default is 8.

```sql
SHOW min_parallel_table_scan_size;
```

This is the minimum table size before PostgreSQL considers parallel scan. Default is 8MB. Tables smaller than this will not get parallel workers.

Expected output (yours will differ):

```
 max_parallel_workers
----------------------
 8
(1 row)

 max_parallel_workers_per_gather
---------------------------------
 2
(1 row)

 max_worker_processes
----------------------
 8
(1 row)

 min_parallel_table_scan_size
------------------------------
 8MB
(1 row)
```

---

## Section 2: Creating a Large Table for Testing

Parallel query only kicks in for tables large enough to benefit. You need a table with enough rows that PostgreSQL decides to use workers.

### Step 1: Create a table with 1,000,000 rows

The `generate_series` function creates a sequence of numbers. This builds a table with one million rows containing random-looking data.

```sql
CREATE TABLE big_table AS
SELECT
    id,
    'customer_' || (id % 1000) AS customer_name,
    (random() * 10000)::numeric(10,2) AS amount,
    now() - (random() * interval '365 days') AS created_at
FROM generate_series(1, 1000000) AS id;
```

Expected output (yours will differ):

```
SELECT 1000000
```

### Step 2: Run ANALYZE on the new table

ANALYZE collects statistics about the table so the query planner knows its size and data distribution. Without this, PostgreSQL might make poor decisions about whether to use parallel workers.

```sql
ANALYZE big_table;
```

### Step 3: Check the table size

The `pg_size_pretty` function converts bytes to a human-readable format.

```sql
SELECT pg_size_pretty(pg_relation_size('big_table')) AS table_size;
```

Expected output (yours will differ):

```
 table_size
------------
 65 MB
(1 row)
```

The table is well above the 8MB `min_parallel_table_scan_size` threshold, so parallel query should kick in.

---

## Section 3: Seeing Parallel Query in Action

### Step 1: Run EXPLAIN ANALYZE on a count query

EXPLAIN ANALYZE runs the query and shows the actual execution plan with timing information. Look for the Gather node and parallel workers.

```sql
EXPLAIN ANALYZE SELECT count(*) FROM big_table;
```

Expected output (yours will differ):

```
                                                             QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------
 Finalize Aggregate  (cost=11614.55..11614.56 rows=1 width=8) (actual time=95.432..97.125 rows=1 loops=1)
   ->  Gather  (cost=11614.33..11614.54 rows=2 width=8) (actual time=95.200..97.110 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         ->  Partial Aggregate  (cost=10614.33..10614.34 rows=1 width=8) (actual time=91.150..91.152 rows=1 loops=3)
               ->  Parallel Seq Scan on big_table  (cost=0.00..9572.67 rows=416667 width=0) (actual time=0.012..52.341 rows=333333 loops=3)
 Planning Time: 0.085 ms
 Execution Time: 97.165 ms
(8 rows)
```

Here is what to look for:

- **Gather** - This is the node that collects results from parallel workers.
- **Workers Planned: 2** - PostgreSQL decided to use 2 parallel workers.
- **Workers Launched: 2** - All 2 workers actually started. If this number is less than planned, the system was too busy to allocate workers.
- **Parallel Seq Scan** - The table scan is happening in parallel across workers.
- **loops=3** - The scan ran 3 times total (2 workers + 1 leader).
- **rows=333333** - Each worker scanned about one-third of the table.

### Step 2: Run a parallel aggregate query

Try a more complex aggregate. The parallel workers each compute a partial result, then the leader combines them.

```sql
EXPLAIN ANALYZE SELECT customer_name, sum(amount), count(*)
FROM big_table
GROUP BY customer_name;
```

Expected output (yours will differ):

```
                                                                QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------
 Finalize HashAggregate  (cost=14831.00..14844.50 rows=1000 width=52) (actual time=215.432..215.812 rows=1000 loops=1)
   Group Key: customer_name
   ->  Gather  (cost=14781.00..14818.00 rows=2000 width=52) (actual time=210.100..213.445 rows=3000 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         ->  Partial HashAggregate  (cost=13781.00..13818.00 rows=1000 width=52) (actual time=207.230..207.510 rows=1000 loops=3)
               ->  Parallel Seq Scan on big_table  (cost=0.00..9572.67 rows=416667 width=26) (actual time=0.015..55.120 rows=333333 loops=3)
 Planning Time: 0.125 ms
 Execution Time: 215.950 ms
(9 rows)
```

Notice the **Partial HashAggregate** - each worker builds its own hash table for the GROUP BY, then the **Finalize HashAggregate** combines them.

---

## Section 4: Disabling Parallel to Compare

### Step 1: Disable parallel workers for this session

The SET command changes a setting for your current session only. Setting `max_parallel_workers_per_gather` to 0 means no parallel workers will be used.

```sql
SET max_parallel_workers_per_gather = 0;
```

### Step 2: Run the same count query

```sql
EXPLAIN ANALYZE SELECT count(*) FROM big_table;
```

Expected output (yours will differ):

```
                                                       QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=18334.00..18334.01 rows=1 width=8) (actual time=185.432..185.434 rows=1 loops=1)
   ->  Seq Scan on big_table  (cost=0.00..15834.00 rows=1000000 width=0) (actual time=0.012..98.541 rows=1000000 loops=1)
 Planning Time: 0.065 ms
 Execution Time: 185.470 ms
(4 rows)
```

Compare the execution times:

- **With parallel (2 workers):** approximately 97 ms
- **Without parallel:** approximately 185 ms

The parallel version is roughly 2x faster because the work is split across 2 workers plus the leader process. The speedup is not a perfect 3x because the Gather node adds overhead to combine results.

### Step 3: Re-enable parallel workers

The RESET command returns the setting to its default value.

```sql
RESET max_parallel_workers_per_gather;
```

### Step 4: Verify it is back to default

```sql
SHOW max_parallel_workers_per_gather;
```

Expected output (yours will differ):

```
 max_parallel_workers_per_gather
---------------------------------
 2
(1 row)
```

---

## Section 5: When Parallel Helps and When It Does Not

### When parallel query helps

- **Large sequential scans** - Scanning millions of rows is the ideal case for parallelism.
- **Aggregate queries** - COUNT, SUM, AVG, MIN, MAX on large tables benefit significantly.
- **Hash joins** - Large hash joins can be parallelized.
- **CREATE INDEX** - PostgreSQL 16 can use parallel workers to build B-tree indexes faster.
- **Reporting queries** - Queries that scan large portions of tables for analytics.

### When parallel query does NOT help

- **Small tables** - Tables under `min_parallel_table_scan_size` (8MB default) will not use parallel workers. The overhead of launching workers would exceed the time saved.
- **Index lookups** - If a query uses an index to fetch a few rows, there is nothing to parallelize.
- **Lock-bound queries** - If the query is waiting for locks, more workers will not help.
- **Write-heavy workloads** - INSERT, UPDATE, DELETE are not parallelized (the writes themselves cannot be split across workers).

### PARALLEL UNSAFE functions

If your query calls a function marked as `PARALLEL UNSAFE`, PostgreSQL will not use parallel workers at all. User-defined functions are PARALLEL UNSAFE by default. If your function is safe to run in parallel, you can mark it:

```sql
-- Example only - do not run this
CREATE OR REPLACE FUNCTION my_function(x int) RETURNS int
AS $$ SELECT x * 2; $$
LANGUAGE SQL PARALLEL SAFE;
```

### Step 1: Verify that small table queries do not use parallel

Run an explain on a small table to confirm no parallel workers are planned.

```sql
EXPLAIN ANALYZE SELECT count(*) FROM orders;
```

Expected output (yours will differ):

```
                                                    QUERY PLAN
------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=20.50..20.51 rows=1 width=8) (actual time=0.035..0.036 rows=1 loops=1)
   ->  Seq Scan on orders  (cost=0.00..18.00 rows=1000 width=0) (actual time=0.008..0.020 rows=1000 loops=1)
 Planning Time: 0.055 ms
 Execution Time: 0.055 ms
(4 rows)
```

No Gather node, no parallel workers. The table is too small to benefit.

---

## Section 6: Tuning for This Server

Your lab server has 2 vCPUs and 736MB RAM. This is a small server, so you need to be conservative with parallel settings.

### Step 1: Review the right settings for 2 cores

On a 2-core server, each parallel worker uses one CPU core. If you allow 2 workers per query, a single query could use all your CPU, leaving nothing for other connections.

Recommended settings for this server:

```sql
-- View current settings (do not change them)
SHOW max_parallel_workers_per_gather;
SHOW max_parallel_workers;
SHOW max_worker_processes;
```

For a 2-core server:

| Setting | Recommended Value | Why |
|---------|-------------------|-----|
| max_parallel_workers_per_gather | 1 | One worker plus the leader = 2 processes = all your cores. Setting this to 2 would oversubscribe. |
| max_parallel_workers | 2 | Total parallel workers across all queries. Matches your core count. |
| max_worker_processes | 8 | Leave at default. This covers parallel workers plus autovacuum and other background processes. |

### Step 2: See what production settings look like

On a larger production server (16 cores), you would use more aggressive settings:

| Setting | 16-core Value | Why |
|---------|---------------|-----|
| max_parallel_workers_per_gather | 4 | Each query can use up to 4 workers. Balances single-query speed with concurrency. |
| max_parallel_workers | 12 | Reserve some cores for non-parallel work. |
| max_worker_processes | 16 | Matches core count. |

The general rule: do not set `max_parallel_workers_per_gather` higher than 25% of your total cores. You need cores for other queries, autovacuum, the WAL writer, and the OS itself.

### Step 3: Set the recommended value for this server

This uses ALTER SYSTEM so the change persists across restarts.

```sql
ALTER SYSTEM SET max_parallel_workers_per_gather = 1;
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
ALTER SYSTEM
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 4: Verify the change

```sql
SHOW max_parallel_workers_per_gather;
```

Expected output (yours will differ):

```
 max_parallel_workers_per_gather
---------------------------------
 1
(1 row)
```

---

## Cleanup

### Step 1: Drop the test table

The big_table was only for this lab. Remove it to free up space.

```sql
DROP TABLE IF EXISTS big_table;
```

### Step 2: Exit psql

```sql
\q
```

### Step 3: Exit the postgres user

```bash
exit
```

---

## Summary

| Concept | What You Learned |
|---------|-----------------|
| Gather node | The query plan node that launches and collects results from parallel workers |
| Workers Planned vs Launched | Planned = what the planner wants; Launched = what was actually available |
| Parallel Seq Scan | Table scan split across multiple workers, each scanning a portion |
| Disabling parallel | SET max_parallel_workers_per_gather = 0 to compare performance |
| When it helps | Large scans, aggregates, hash joins, CREATE INDEX |
| When it does not help | Small tables, index lookups, lock-bound queries, writes |
| Tuning for server size | 2 cores = 1 worker per gather; 16 cores = 4 workers per gather |

Parallel query is one of the easiest performance wins in PostgreSQL - it requires no application changes. The key is setting the worker counts appropriately for your hardware so you get parallelism without overloading the server.
