# Scenario 10 - Parallel Workers Disabled

**Severity:** MEDIUM
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Aggregate queries on large tables are running
much slower than expected. The server has multiple CPU
cores but only one core is active during queries.
A configuration review was done recently to 'reduce
resource usage' during a maintenance window.
```

---

## Key Concepts for Revision

- **Parallel query in PostgreSQL** - Since PostgreSQL 9.6, the planner can split large sequential scans, aggregations, and joins across multiple worker processes. Each worker scans a portion of the data, and results are gathered by the leader process. This can dramatically speed up queries on large tables.

- **Three settings control parallel workers** - `max_parallel_workers` sets the total pool of parallel workers across all sessions. `max_parallel_workers_per_gather` limits how many workers a single query can use. `max_parallel_maintenance_workers` controls workers for `CREATE INDEX` and `VACUUM`. All three must be non-zero for parallel queries to work.

- **When parallelism kicks in** - The planner considers parallel plans only when: (1) the table is large enough (controlled by `min_parallel_table_scan_size`, default 8MB), (2) the query involves a supported operation (seq scan, hash join, aggregate, etc.), (3) the cost estimate justifies the overhead of spawning workers. Setting workers to 0 prevents parallelism entirely.

- **Worker count per table** - PostgreSQL automatically calculates how many workers to assign based on table size. For every 3x increase in table size beyond `min_parallel_table_scan_size`, one additional worker is added, up to `max_parallel_workers_per_gather`. You can also set per-table hints with `ALTER TABLE ... SET (parallel_workers = N)`.

- **EXPLAIN shows parallel plans** - In EXPLAIN output, look for `Gather` or `Gather Merge` nodes. Below them, you will see `Parallel Seq Scan`, `Parallel Index Scan`, or `Parallel Hash Join`. The `Workers Planned` and `Workers Launched` fields show how many workers were assigned.

---

## Diagnostic Steps

### Step 1 - Run an aggregate query on the large table

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
EXPLAIN (ANALYZE) SELECT txn_type, SUM(amount), COUNT(*) FROM chaos10_transactions GROUP BY txn_type;
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 HashAggregate  (cost=2500.00..2500.02 rows=2 width=...)
   Group Key: txn_type
   -> Seq Scan on chaos10_transactions  (cost=0.00..2000.00 rows=100000 ...)
   Planning Time: 0.200 ms
   Execution Time: 150.000 ms
```

Notice: no `Gather` node, no `Parallel Seq Scan`. The query runs single-threaded.

### Step 2 - Check parallel worker settings

```sql
SHOW max_parallel_workers_per_gather;
```

Expected output:

```
 max_parallel_workers_per_gather
---------------------------------
 0
(1 row)
```

```sql
SHOW max_parallel_workers;
```

Expected output:

```
 max_parallel_workers
----------------------
 0
(1 row)
```

```sql
SHOW max_parallel_maintenance_workers;
```

Expected output:

```
 max_parallel_maintenance_workers
----------------------------------
 0
(1 row)
```

All three are set to 0. Parallel query is completely disabled.

### Step 3 - Check how many CPU cores are available

```sql
\q
```

```bash
exit
```

```bash
nproc
```

Expected output (yours will differ):

```
2
```

The server has 2 CPU cores, so parallel queries could use at least 1 worker (plus the leader process).

### Step 4 - Find where the settings were changed

```bash
sudo -iu postgres
```

```bash
grep parallel /opt/pgsql/data/postgresql.auto.conf
```

Expected output:

```
max_parallel_workers_per_gather = '0'
max_parallel_workers = '0'
max_parallel_maintenance_workers = '0'
```

---

## Resolution

### Step 1 - Re-enable parallel workers

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
ALTER SYSTEM SET max_parallel_workers_per_gather = 2;
```

Expected output:

```
ALTER SYSTEM
```

This allows each query to use up to 2 parallel workers. The default is 2.

```sql
ALTER SYSTEM SET max_parallel_workers = 8;
```

Expected output:

```
ALTER SYSTEM
```

This sets the total pool of parallel workers across all sessions. The default is 8.

```sql
ALTER SYSTEM SET max_parallel_maintenance_workers = 2;
```

Expected output:

```
ALTER SYSTEM
```

This re-enables parallel workers for `CREATE INDEX` and `VACUUM`. The default is 2.

### Step 2 - Reload configuration

```sql
SELECT pg_reload_conf();
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 3 - Verify settings

```sql
SHOW max_parallel_workers_per_gather;
```

Expected output:

```
 max_parallel_workers_per_gather
---------------------------------
 2
(1 row)
```

```sql
SHOW max_parallel_workers;
```

Expected output:

```
 max_parallel_workers
----------------------
 8
(1 row)
```

### Step 4 - Verify parallel query plans

```sql
EXPLAIN (ANALYZE) SELECT txn_type, SUM(amount), COUNT(*) FROM chaos10_transactions GROUP BY txn_type;
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Finalize HashAggregate  (cost=... rows=2 width=...)
   Group Key: txn_type
   -> Gather  (cost=... rows=4 width=...)
        Workers Planned: 2
        Workers Launched: 2
        -> Partial HashAggregate  (cost=... rows=2 width=...)
              Group Key: txn_type
              -> Parallel Seq Scan on chaos10_transactions  (cost=...)
   Planning Time: 0.150 ms
   Execution Time: 50.000 ms
```

The plan now shows `Gather`, `Parallel Seq Scan`, and `Workers Planned: 2`. Execution time should be noticeably faster.

```sql
\q
```

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- max_parallel_workers_per_gather is at least 1
- max_parallel_workers is at least 1
- EXPLAIN shows a parallel plan on large table
- postgresql.auto.conf does not have parallel workers set to 0

---

## Interview Discussion Points

1. **When should you disable parallel queries?** - On single-core machines (parallel workers compete for the same CPU). On systems with many concurrent connections where CPU is already saturated. During bulk loading (parallel workers add overhead without benefit for INSERT operations). Some OLTP workloads with many short queries may not benefit because the overhead of spawning workers exceeds the scan time.

2. **What is the difference between max_parallel_workers and max_worker_processes?** - `max_worker_processes` is the total cap on all background worker processes (parallel query workers, logical replication workers, custom extensions). `max_parallel_workers` is the subset available for parallel queries. `max_parallel_workers` cannot exceed `max_worker_processes`. Note: `max_worker_processes` requires a restart to change.

3. **How does parallelism affect OLTP vs OLAP workloads?** - OLAP (analytics) benefits greatly - large scans, aggregations, and joins are parallelized. OLTP (many small transactions) benefits less because individual queries touch few rows. In mixed workloads, limit `max_parallel_workers_per_gather` to prevent a single analytical query from consuming all CPU at the expense of OLTP traffic.

4. **Can parallel workers cause contention?** - Yes. Each parallel worker is a separate PostgreSQL process with its own memory allocation (work_mem). Three workers running a sort each allocate work_mem independently. On a system with 100 concurrent queries each spawning 2 workers, that is 300 processes competing for CPU and memory. This is why `max_parallel_workers` exists as a global cap.

5. **What operations support parallel execution in PostgreSQL 16?** - Sequential scans, index scans, bitmap heap scans, hash joins, merge joins, nested loop joins, hash aggregates, sort aggregates, append (for partitioned tables), and some utility commands (CREATE INDEX, VACUUM). Notably, writes (INSERT/UPDATE/DELETE) are not parallelized. Foreign data wrappers and custom scan providers may or may not support parallelism.
