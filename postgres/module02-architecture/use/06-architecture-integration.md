# Exercise 06 - Architecture Integration

**Time estimate:** 25-30 minutes
**Prerequisites:** Exercises 01-05 complete - you understand processes, memory, storage, query processing, and connections.

---

## Objective

Combine all four BUILD topics into a single diagnostic workflow and produce a health report from live data. By the end of this exercise, you should be able to assess a running PostgreSQL instance in under 10 minutes and identify areas of concern.

---

## Step 1 - Start a pgbench Workload

On **NODE1** (pg-primary), start a 60-second pgbench workload to generate realistic activity:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pgbench -c 10 -j 2 -T 60 labdb
```

The `-c 10` flag opens 10 concurrent client connections. The `-j 2` flag uses 2 worker threads. The `-T 60` flag runs the workload for 60 seconds. This simulates a moderate OLTP workload with mixed reads and writes.

**Expected:** After 60 seconds, pgbench prints a summary with transaction count and TPS (transactions per second). Note the TPS number - you will reference it in your health report.

> **Concept:** pgbench is PostgreSQL's built-in benchmarking tool. The default workload runs a mix of SELECT, UPDATE, and INSERT queries against the pgbench tables. Running it before collecting metrics ensures there is meaningful data in the statistics views - cache hit ratios, buffer writes, connection counts all reflect real activity rather than an idle server.

---

## Step 2 - Collect Process Metrics

```bash
psql -d labdb
```

Count all PostgreSQL processes by type:

```sql
SELECT backend_type, count(*)
FROM pg_stat_activity
GROUP BY backend_type
ORDER BY count(*) DESC;
```

**Expected:** Shows all process types: `client backend`, `background worker`, `checkpointer`, `background writer`, `walwriter`, `autovacuum launcher`, `logical replication launcher`, and any active autovacuum workers. After pgbench finishes, `client backend` count should be 1 (your session).

Count active vs idle backends:

```sql
SELECT
    state,
    count(*)
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state;
```

**Expected:** Your session shows as `active`. Any remaining pgbench connections (if still connected) show as `idle`.

---

## Step 3 - Collect Memory and Cache Metrics

Check the cache hit ratio:

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

**Expected:** After the pgbench workload, the hit ratio should be high (above 95%) because pgbench operates on a relatively small working set.

Find the top 5 relations in the buffer cache:

```sql
SELECT
    c.relname,
    c.relkind,
    count(*) AS buffers,
    pg_size_pretty(count(*) * 8192) AS cached_size
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = c.relfilenode
WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = 'labdb')
GROUP BY c.relname, c.relkind
ORDER BY buffers DESC
LIMIT 5;
```

**Expected:** `pgbench_accounts` dominates the cache. You will also see its primary key index and possibly `pgbench_tellers` or `pgbench_branches`.

---

## Step 4 - Collect Background Writer Statistics

```sql
SELECT
    checkpoints_timed,
    checkpoints_req,
    buffers_checkpoint,
    buffers_clean,
    buffers_backend,
    round(100.0 * buffers_backend / GREATEST(buffers_checkpoint + buffers_clean + buffers_backend, 1), 2) AS pct_backend_writes,
    maxwritten_clean,
    backend_fsync
FROM pg_stat_bgwriter;
```

**Expected:** After the pgbench workload, `buffers_backend` may have increased - pgbench writes generate dirty pages. A `pct_backend_writes` above 10% suggests the background writer is not keeping up. `backend_fsync` should be 0 - if it is greater than 0, backends are doing their own fsync calls, which is a serious performance problem.

> **Concept:** The `backend_fsync` counter should always be 0 in production. A non-zero value means the checkpointer's fsync request queue overflowed and backends had to perform synchronous disk writes themselves. This causes severe latency spikes. The fix is to increase `checkpoint_completion_target` or reduce checkpoint frequency.

---

## Step 5 - Collect Storage Metrics

Check table sizes:

```sql
SELECT
    relname,
    pg_size_pretty(pg_relation_size(oid)) AS table_size,
    pg_size_pretty(pg_total_relation_size(oid)) AS total_size,
    pg_size_pretty(pg_total_relation_size(oid) - pg_relation_size(oid)) AS index_and_toast_size
FROM pg_class
WHERE relname LIKE 'pgbench_%' AND relkind = 'r'
ORDER BY pg_total_relation_size(oid) DESC;
```

**Expected:** `pgbench_accounts` is the largest table. `total_size` includes indexes and TOAST data. The difference between `total_size` and `table_size` shows how much space indexes consume.

Check for bloat in the most active table:

```sql
SELECT
    dead_tuple_count,
    dead_tuple_percent,
    free_space,
    free_percent
FROM pgstattuple('pgbench_accounts');
```

**Expected:** After the pgbench workload (which runs UPDATEs), there may be some dead tuples. If autovacuum ran during the workload, `dead_tuple_count` may already be low.

---

## Step 6 - Collect a Query Plan

Examine the plan for one of the pgbench default queries:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT abalance FROM pgbench_accounts WHERE aid = 12345;
```

**Expected:** An Index Scan using the primary key index. The `shared hit` count shows how many pages came from the buffer cache. This is the most common query in the pgbench workload - a primary key lookup.

```sql
EXPLAIN (ANALYZE, BUFFERS)
UPDATE pgbench_accounts SET abalance = abalance + 100 WHERE aid = 12345;
```

**Expected:** An Index Scan for the lookup, followed by an update. The BUFFERS output shows `shared dirtied` - pages modified by the UPDATE.

> **Concept:** In a real health check, you would examine the slowest queries from `pg_stat_statements` (not covered in this module). For now, examining the pgbench default queries demonstrates how to read plans for both reads and writes. The key metrics are: scan type (index vs sequential), estimated vs actual rows, and buffer hit vs read ratio.

---

## Step 7 - Compile the Health Report

Exit psql:

```sql
\q
```

Create a health report file:

```bash
vi /tmp/architecture_health_report.txt
```

Use this template and fill in the values you collected:

```
=== PostgreSQL Architecture Health Report ===
Date: <today's date>
Server: pg-primary (NODE1)
PostgreSQL Version: 16

--- Process Summary ---
Total backend types: <count from Step 2>
Active client backends: <count>
Background workers: <list>

--- Memory / Cache ---
Cache hit ratio: <value>%
Top cached relation: <name> (<cached size>)
shared_buffers: <value>

--- Background Writer ---
Checkpoints (timed/requested): <timed> / <req>
Backend write percentage: <pct>%
backend_fsync: <value>

--- Storage ---
Largest table: <name> (<total size>)
Dead tuple count (pgbench_accounts): <count>
Dead tuple percentage: <pct>%

--- Query Performance ---
pgbench TPS: <value>
Primary key lookup: Index Scan, shared hit=<value>

--- Concern ---
<identify one metric that is suboptimal>

--- Recommendation ---
<suggest a specific config change or action>
```

Save and exit vi (`:wq`).

> **Concept:** A structured health report forces you to look at every layer of the architecture systematically. In production, you would run this check weekly or after any significant change (config update, major release, hardware migration). The most common findings: low cache hit ratio (increase shared_buffers), high backend write percentage (tune bgwriter parameters), excessive dead tuples (check autovacuum settings), and connection count near max_connections (implement connection pooling).

```bash
exit
```

---

## Step 8 - Review Your Report

Read through your report and verify that every value makes sense. Ask yourself:
- Is the cache hit ratio consistent with the workload?
- Does the background writer distribution look healthy?
- Are there dead tuples that autovacuum should have cleaned?
- Did the pgbench query plans use indexes as expected?

If any value looks wrong, go back and re-collect that metric. The ability to spot anomalies in a health report is the skill this exercise builds.

---

## Checkpoint

Before continuing, confirm:
- [ ] You ran a pgbench workload and noted the TPS
- [ ] You collected process counts by type and state
- [ ] You measured the cache hit ratio and identified top cached relations
- [ ] You interpreted the background writer statistics and calculated backend write percentage
- [ ] You checked table sizes and bloat levels
- [ ] You examined EXPLAIN ANALYZE BUFFERS output for both a SELECT and an UPDATE
- [ ] You compiled a structured health report with all metrics
- [ ] You identified at least one concern and recommended a specific action

---

**Next:** [Checklist - Knowledge Check](checklist.md)
