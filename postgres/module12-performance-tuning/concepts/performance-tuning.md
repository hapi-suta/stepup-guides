# PostgreSQL Performance Tuning

## Why This Module Matters

A slow database is rarely the database's fault - it's a missing index, a bad query plan,
or a misconfigured parameter. PostgreSQL gives you EXPLAIN to see exactly what the
planner is doing and why. The skill is reading that output, understanding what the
planner chose and what alternatives exist, then making targeted changes.

---

## EXPLAIN and EXPLAIN ANALYZE

### EXPLAIN - The Estimated Plan

```sql
EXPLAIN SELECT * FROM orders WHERE customer_id = 42;
```

```
Seq Scan on orders  (cost=0.00..1520.00 rows=15 width=64)
  Filter: (customer_id = 42)
```

This shows what the planner intends to do. It does NOT execute the query. The numbers
are estimates based on table statistics.

### EXPLAIN ANALYZE - The Actual Plan

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 42;
```

```
Seq Scan on orders  (cost=0.00..1520.00 rows=15 width=64) (actual time=0.015..12.450 rows=12 loops=1)
  Filter: (customer_id = 42)
  Rows Removed by Filter: 99988
Planning Time: 0.085 ms
Execution Time: 12.480 ms
```

This actually runs the query and shows real timing and row counts. Use this for
tuning, but be careful - the query executes, so a DELETE will actually delete rows.
Wrap destructive queries in a transaction:

```sql
BEGIN;
EXPLAIN ANALYZE DELETE FROM orders WHERE status = 'draft';
ROLLBACK;
```

### Reading the Output

```
Seq Scan on orders  (cost=0.00..1520.00 rows=15 width=64)
                      ^         ^         ^        ^
                      |         |         |        +-- average row width in bytes
                      |         |         +-- estimated rows returned
                      |         +-- total cost (arbitrary units)
                      +-- startup cost (cost before first row is returned)
```

The cost is in arbitrary units - what matters is comparing costs between different
plans, not the absolute number.

### EXPLAIN Options

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...
```

- **ANALYZE** - actually run the query
- **BUFFERS** - show buffer hit/read counts (requires ANALYZE)
- **FORMAT** - TEXT (default), JSON, YAML, XML
- **VERBOSE** - show output columns, schema-qualified names
- **SETTINGS** - show non-default planner settings that affect the plan

BUFFERS is particularly useful:

```
Seq Scan on orders  (cost=...) (actual time=...)
  Buffers: shared hit=520 read=980
```

520 pages came from cache, 980 came from disk. High `read` relative to `hit` means
the working set doesn't fit in shared_buffers.

---

## Node Types

Every EXPLAIN plan is a tree of nodes. Data flows from child nodes up to parent nodes.

### Scan Nodes (Leaf Nodes - Read Data)

**Seq Scan** - reads every page of the table sequentially.

```
Seq Scan on orders  (cost=0.00..1520.00 rows=100000 width=64)
```

Not always bad. For small tables or queries returning most rows, a Seq Scan is optimal.

**Index Scan** - uses an index to find specific rows, then fetches the full tuple from
the table.

```
Index Scan using orders_customer_id_idx on orders  (cost=0.29..8.50 rows=12 width=64)
  Index Cond: (customer_id = 42)
```

Best for highly selective queries (returning a small percentage of rows).

**Index Only Scan** - reads all needed data from the index alone, never touches the table.
Only possible when all columns in the query are in the index (covering index).

```
Index Only Scan using orders_cust_status_idx on orders  (cost=0.29..4.30 rows=12 width=8)
  Index Cond: (customer_id = 42)
  Heap Fetches: 0
```

`Heap Fetches: 0` means it never went to the table. This is the fastest scan type.

**Bitmap Index Scan + Bitmap Heap Scan** - two-step process. First, scan the index and
build a bitmap of which pages contain matching rows. Then, read those pages in order.

```
Bitmap Heap Scan on orders  (cost=12.50..520.00 rows=500 width=64)
  Recheck Cond: (status = 'pending')
  ->  Bitmap Index Scan on orders_status_idx  (cost=0.00..12.37 rows=500 width=0)
        Index Cond: (status = 'pending')
```

Used when too many rows for an Index Scan (random I/O would be expensive) but too
few for a Seq Scan. Also used to combine multiple indexes with BitmapAnd/BitmapOr.

### Join Nodes

**Nested Loop** - for each row in the outer table, scan the inner table.

```
Nested Loop  (cost=0.29..125.00 rows=12 width=128)
  ->  Index Scan using customers_pkey on customers  (cost=0.29..8.30 rows=1 width=64)
  ->  Index Scan using orders_customer_id_idx on orders  (cost=0.29..8.50 rows=12 width=64)
```

Best when the outer side is small (few rows). Performance degrades with large outer sets.

**Hash Join** - builds a hash table from one input, then probes it with the other.

```
Hash Join  (cost=100.00..850.00 rows=5000 width=128)
  Hash Cond: (orders.customer_id = customers.id)
  ->  Seq Scan on orders  (cost=0.00..600.00 rows=50000 width=64)
  ->  Hash  (cost=50.00..50.00 rows=2000 width=64)
        ->  Seq Scan on customers  (cost=0.00..50.00 rows=2000 width=64)
```

Best for joining large tables. Requires enough work_mem to hold the hash table. If the
hash table doesn't fit in work_mem, it spills to disk (Batches > 1).

**Merge Join** - sorts both inputs and merges them. Efficient when both sides are
already sorted (e.g., from an index scan).

```
Merge Join  (cost=0.56..1200.00 rows=5000 width=128)
  Merge Cond: (orders.customer_id = customers.id)
  ->  Index Scan using orders_customer_id_idx on orders
  ->  Index Scan using customers_pkey on customers
```

### Other Common Nodes

- **Sort** - sorts input rows. Check if an index could provide the order instead.
- **Aggregate** - computes SUM, COUNT, AVG, etc.
- **HashAggregate** - GROUP BY using a hash table
- **Limit** - stops after N rows
- **Materialize** - caches results of a subplan for reuse

---

## The Cost Model

The planner assigns costs using these parameters:

| Parameter              | Default | Meaning                                    |
|------------------------|---------|--------------------------------------------|
| seq_page_cost          | 1.0     | Cost of reading one sequential page         |
| random_page_cost       | 4.0     | Cost of reading one random page             |
| cpu_tuple_cost         | 0.01    | Cost of processing one row                  |
| cpu_index_tuple_cost   | 0.005   | Cost of processing one index entry          |
| cpu_operator_cost      | 0.0025  | Cost of processing one operator             |
| effective_cache_size   | 4 GB    | Planner's estimate of available cache       |

The ratio of `random_page_cost` to `seq_page_cost` drives many decisions. On SSDs,
random reads are nearly as fast as sequential reads. Lower `random_page_cost` to 1.1-1.5
for SSD storage:

```sql
ALTER SYSTEM SET random_page_cost = 1.1;
```

This makes the planner more willing to choose index scans over sequential scans.

`effective_cache_size` doesn't allocate memory - it tells the planner how much data
is likely to be in the OS page cache + shared_buffers combined. Set it to about 75%
of total RAM.

---

## Key Memory Parameters

### shared_buffers

PostgreSQL's own page cache. Every read goes through shared_buffers first.

```
+--------+     +-----------------+     +--------+
|  Query | --> | shared_buffers  | --> |  Disk  |
+--------+     | (PostgreSQL     |     +--------+
               |  page cache)    |
               +-----------------+
                       |
               Also backed by OS page cache
```

Recommendation: 25% of total RAM. Going higher can hurt because PostgreSQL's cache
competes with the OS page cache.

- 16 GB RAM server: `shared_buffers = 4GB`
- 64 GB RAM server: `shared_buffers = 16GB`

### work_mem

Memory for sort operations and hash tables per operation (not per connection). A single
complex query can use multiple work_mem allocations.

```sql
-- Default is 4MB - often too low for analytical queries
ALTER SYSTEM SET work_mem = '64MB';
```

Be careful: if you have 100 connections each running queries with 3 sort nodes,
that's 100 * 3 * 64MB = 19.2 GB.

Better approach - set it low globally and raise per-session for analytical work:

```sql
-- Global default
ALTER SYSTEM SET work_mem = '16MB';

-- For a specific reporting session
SET work_mem = '256MB';
```

Signs work_mem is too low: `Sort Method: external merge Disk` in EXPLAIN output.

### maintenance_work_mem

Memory for maintenance operations: VACUUM, CREATE INDEX, ALTER TABLE ADD FOREIGN KEY.

```sql
ALTER SYSTEM SET maintenance_work_mem = '1GB';
```

This can be much higher than work_mem because only a few maintenance operations run
simultaneously.

### effective_cache_size

Already covered above - not a memory allocation, just a planner hint. Set to 75% of RAM.

---

## WAL Tuning

Write-Ahead Logging (WAL) parameters affect write performance and crash recovery time.

### Key Parameters

**wal_buffers** - shared memory for WAL records before they're written to disk.
Default is 1/32 of shared_buffers, capped at 64MB. Usually fine at the default.

**max_wal_size** - maximum WAL accumulated between checkpoints. Larger values mean:
- Fewer checkpoints (less I/O overhead)
- Longer crash recovery time

```sql
ALTER SYSTEM SET max_wal_size = '4GB';   -- default is 1GB
ALTER SYSTEM SET min_wal_size = '1GB';
```

**checkpoint_completion_target** - spreads checkpoint I/O over this fraction of the
checkpoint interval. Default is 0.9 (spread over 90% of the interval).

```
checkpoint_completion_target = 0.5:  |||||||........  (write fast, then idle)
checkpoint_completion_target = 0.9:  |..|..|..|..|.  (spread out writes)
```

Higher values reduce I/O spikes. The default of 0.9 is good for most workloads.

---

## Index Types

### B-tree (Default)

The workhorse. Supports equality and range queries on sortable data types.

```sql
CREATE INDEX ON orders (customer_id);
CREATE INDEX ON orders (created_at DESC);
```

Use for: `=`, `<`, `>`, `<=`, `>=`, `BETWEEN`, `IN`, `IS NULL`, `ORDER BY`

### Hash

Only supports equality comparisons. Slightly faster than B-tree for pure equality
lookups. Rarely used since B-tree handles equality well.

```sql
CREATE INDEX ON sessions USING hash (session_token);
```

Use for: `=` only, and only when you're sure you never need range queries.

### GIN (Generalized Inverted Index)

For values that contain multiple elements - arrays, JSONB, full-text search.

```sql
CREATE INDEX ON products USING gin (tags);           -- array column
CREATE INDEX ON documents USING gin (metadata);       -- JSONB column
CREATE INDEX ON articles USING gin (to_tsvector('english', body));  -- full-text
```

Use for: `@>`, `<@`, `?`, `?|`, `?&` (containment/existence operators), full-text `@@`

GIN indexes are slower to update than B-tree but very fast for lookups.

### GiST (Generalized Search Tree)

For geometric data, ranges, and full-text search (alternative to GIN).

```sql
CREATE INDEX ON events USING gist (duration);         -- range type
CREATE INDEX ON locations USING gist (coordinates);   -- PostGIS geometry
```

Use for: range overlap (`&&`), containment (`@>`), nearest-neighbor (`<->`)

### BRIN (Block Range Index)

Tiny index for physically ordered data. Stores min/max values per block range.

```sql
CREATE INDEX ON sensor_data USING brin (recorded_at);
```

Use for: large tables where the indexed column correlates with physical row order
(e.g., timestamp columns in append-only tables). BRIN indexes are 1000x smaller
than B-tree but only effective when data is naturally ordered.

---

## Connection Pooling

### The Problem

PostgreSQL forks a new process for each connection. Each connection uses ~5-10 MB of
memory. At 500 connections, that's 2.5-5 GB just for connection overhead.

Worse, PostgreSQL performance degrades with too many active connections. A server with
200 active queries often performs worse than one with 20, because of lock contention
and context switching.

### PgBouncer

PgBouncer sits between your application and PostgreSQL. It maintains a small pool
of actual database connections and multiplexes application connections onto them.

```
Application (500 connections)
       |
   PgBouncer (pool of 20 connections)
       |
   PostgreSQL (20 backend processes)
```

Pool modes:
- **session** - connection returned to pool when client disconnects. Safest.
- **transaction** - connection returned after each transaction. Best throughput.
  Cannot use session-level features (SET, prepared statements, LISTEN/NOTIFY).
- **statement** - connection returned after each statement. Most restrictive.
  Cannot use multi-statement transactions.

Transaction mode is the most common for web applications.

---

## Query Optimization Patterns

### CTEs vs Subqueries

Before PostgreSQL 12, CTEs were optimization fences - the planner couldn't push
predicates into them. Since PG 12, CTEs are inlined by default (like subqueries).

```sql
-- PG 12+: these are equivalent in performance
WITH pending AS (SELECT * FROM orders WHERE status = 'pending')
SELECT * FROM pending WHERE created_at > now() - interval '1 day';

SELECT * FROM orders WHERE status = 'pending' AND created_at > now() - interval '1 day';
```

Use `MATERIALIZED` to force the old behavior when you want the CTE executed exactly once:

```sql
WITH pending AS MATERIALIZED (SELECT * FROM orders WHERE status = 'pending')
SELECT * FROM pending WHERE created_at > '2024-01-01';
```

### Covering Indexes

Include all columns the query needs in the index to enable Index Only Scans:

```sql
-- Query:
SELECT customer_id, status, total FROM orders WHERE customer_id = 42;

-- Covering index (INCLUDE for non-searchable payload columns):
CREATE INDEX ON orders (customer_id) INCLUDE (status, total);
```

The INCLUDE columns are stored in the index leaf pages but not in the index tree.
They can't be used for filtering, only for avoiding table heap fetches.

### Partial Indexes

Index only the rows that matter:

```sql
-- Only 5% of orders are 'pending', but you query them constantly
CREATE INDEX ON orders (created_at) WHERE status = 'pending';
```

This index is much smaller than a full index and only maintained for matching rows.
The query must include the WHERE clause for the planner to use it.

### Expression Indexes

Index on a computed value:

```sql
CREATE INDEX ON users (lower(email));

-- Now this uses the index:
SELECT * FROM users WHERE lower(email) = 'alice@example.com';
```

---

## Parallel Query

PostgreSQL can split large operations across multiple workers.

### How It Works

```
       Gather (or Gather Merge)
       /    |    \
  Worker Worker Worker    <-- each processes a portion of the table
       \    |    /
        Results
```

The planner chooses parallel execution when the table is large enough and the
query type supports it.

### Key Parameters

```sql
max_parallel_workers_per_gather = 2    -- workers per query node (default 2)
max_parallel_workers = 8               -- total parallel workers across all queries
max_worker_processes = 8               -- total background workers
min_parallel_table_scan_size = 8MB     -- minimum table size for parallel scan
parallel_tuple_cost = 0.1              -- cost of passing a tuple between workers
parallel_setup_cost = 1000             -- cost of launching workers
```

### When Parallel Helps

- Large sequential scans
- Aggregates over big tables
- Hash joins with large inputs
- B-tree index creation (CREATE INDEX)

### When Parallel Doesn't Help

- Small tables
- Index lookups returning few rows
- Queries already bound by lock waits or I/O
- Functions marked PARALLEL UNSAFE

### Checking Parallel Execution

```sql
EXPLAIN ANALYZE SELECT count(*) FROM big_table;
```

```
Finalize Aggregate  (actual time=150.00..150.01 rows=1)
  ->  Gather  (actual time=50.00..149.95 rows=3)
        Workers Planned: 2
        Workers Launched: 2
        ->  Partial Aggregate  (actual time=45.00..45.01 rows=1)
              ->  Parallel Seq Scan on big_table  (actual time=0.01..30.00 rows=333333)
```

"Workers Launched: 2" confirms parallel execution. If Workers Launched < Workers Planned,
you've hit the `max_parallel_workers` limit.

---

## A Tuning Workflow

When a query is slow:

1. **Run EXPLAIN (ANALYZE, BUFFERS)** - get the actual execution plan
2. **Compare estimated vs actual rows** - large differences mean stale statistics (run ANALYZE)
3. **Look for Seq Scans on large tables** - consider adding an index
4. **Check for Sort: external merge Disk** - increase work_mem
5. **Check buffer hit ratio** - low hits mean data isn't cached
6. **Check join types** - Nested Loop on large sets is usually wrong (check join conditions)
7. **Verify index usage** - does the right index exist? Is the planner choosing it?
8. **Consider partial or covering indexes** if a regular index isn't enough

---

## Key Takeaways

1. Always use EXPLAIN (ANALYZE, BUFFERS) to see what's actually happening, not just what the planner estimates
2. The planner picks plans based on cost estimates - stale statistics cause bad plans (run ANALYZE)
3. shared_buffers = 25% of RAM, effective_cache_size = 75% of RAM, work_mem = set per-session
4. Lower random_page_cost to 1.1-1.5 for SSD storage
5. B-tree covers 90% of indexing needs; GIN for arrays/JSONB, BRIN for append-only timestamp data
6. PgBouncer in transaction mode is the standard for web applications
7. Covering indexes (INCLUDE) and partial indexes are powerful optimizations most people overlook
8. Parallel query helps with large scans and aggregates but has diminishing returns past 4-8 workers
