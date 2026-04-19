# Exercise 04 - Query Pipeline Diagnostics

**Time estimate:** 25-30 minutes
**Prerequisites:** BUILD phase complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9 with labdb (pgbench data), postgres user, PGDATA at `/opt/pgsql/data`. Extensions installed: pg_buffercache, pageinspect, pgstattuple.

---

## Objective

Provoke errors at each stage of the PostgreSQL query processing pipeline and interpret EXPLAIN output. By the end of this exercise, you should be able to read a multi-node EXPLAIN plan, identify which stage a query fails at, and spot discrepancies between estimated and actual rows.

---

## Step 1 - Provoke Parser and Analyzer Errors

On **NODE1** (pg-primary), switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -d labdb
```

Send a query with a syntax error to trigger a **parser** failure:

```sql
SELEC * FROM pgbench_accounts;
```

**Expected:**

```
ERROR:  syntax error at or near "SELEC"
LINE 1: SELEC * FROM pgbench_accounts;
        ^
```

The parser checks raw SQL syntax before anything else. It does not know whether tables or columns exist - it only checks grammar.

Now send a query that parses correctly but references a table that does not exist. This triggers the **analyzer**:

```sql
SELECT * FROM nonexistent_table;
```

**Expected:**

```
ERROR:  relation "nonexistent_table" does not exist
LINE 1: SELECT * FROM nonexistent_table;
                      ^
```

Now trigger an analyzer error with a type mismatch:

```sql
SELECT * FROM pgbench_accounts WHERE aid = 'not_a_number';
```

**Expected:**

```
ERROR:  invalid input syntax for type integer: "not_a_number"
```

The analyzer resolves table names, column names, and data types. It knows that `aid` is an integer and rejects the string comparison.

> **Concept:** PostgreSQL processes every query through 5 stages in this order: (1) Parser - checks SQL grammar and builds a parse tree, (2) Analyzer - resolves names and types, validates permissions, (3) Rewriter - expands views and applies rules, (4) Planner/Optimizer - generates the execution plan with lowest estimated cost, (5) Executor - runs the plan and returns results. A failure at an earlier stage means the query never reaches later stages.

---

## Step 2 - Prove the Rewriter Expands Views

Create a simple view:

```sql
CREATE VIEW account_summary AS
SELECT aid, bid, abalance
FROM pgbench_accounts
WHERE abalance > 0;
```

Now EXPLAIN a query against the view:

```sql
EXPLAIN SELECT * FROM account_summary WHERE bid = 1;
```

**Expected:** The plan does not mention the view `account_summary` at all. Instead, it shows operations directly on `pgbench_accounts` with the combined filter conditions (`abalance > 0 AND bid = 1`):

```
                                QUERY PLAN
--------------------------------------------------------------------------
 Seq Scan on pgbench_accounts  (cost=0.00..xxxxx rows=xx width=xx)
   Filter: ((abalance > 0) AND (bid = 1))
```

> **Concept:** The rewriter runs before the planner. It replaces the view reference with the underlying query definition and merges the WHERE clauses. By the time the planner sees the query, the view is gone - it is as if you wrote the expanded query yourself. This is why views have zero runtime overhead compared to writing the equivalent query directly.

Clean up:

```sql
DROP VIEW account_summary;
```

---

## Step 3 - Compare EXPLAIN vs EXPLAIN ANALYZE

Run EXPLAIN without ANALYZE:

```sql
EXPLAIN SELECT * FROM pgbench_accounts WHERE aid = 12345;
```

**Expected:** Shows the plan with estimated costs and row counts:

```
                                        QUERY PLAN
------------------------------------------------------------------------------------------
 Index Scan using pgbench_accounts_pkey on pgbench_accounts  (cost=0.42..8.44 rows=1 width=97)
   Index Cond: (aid = 12345)
```

Now run EXPLAIN with ANALYZE:

```sql
EXPLAIN ANALYZE SELECT * FROM pgbench_accounts WHERE aid = 12345;
```

**Expected:** The same plan structure, but now with actual execution metrics:

```
                                        QUERY PLAN
------------------------------------------------------------------------------------------
 Index Scan using pgbench_accounts_pkey on pgbench_accounts  (cost=0.42..8.44 rows=1 width=97) (actual time=0.025..0.026 rows=1 loops=1)
   Index Cond: (aid = 12345)
 Planning Time: 0.085 ms
 Execution Time: 0.042 ms
```

Document the differences:

| Field | EXPLAIN Only | EXPLAIN ANALYZE |
|---|---|---|
| cost (startup..total) | Yes | Yes |
| rows (estimated) | Yes | Yes |
| width | Yes | Yes |
| actual time | No | Yes |
| actual rows | No | Yes |
| loops | No | Yes |
| Planning Time | No | Yes |
| Execution Time | No | Yes |

> **Concept:** `EXPLAIN` asks the planner to show the plan without running the query. It is safe to run on any query, including `DELETE` or `UPDATE`. `EXPLAIN ANALYZE` actually executes the query and measures real time and row counts. WARNING: `EXPLAIN ANALYZE` on a `DELETE FROM users;` WILL delete all users. Always use a transaction and rollback when analyzing destructive queries: `BEGIN; EXPLAIN ANALYZE DELETE FROM ...; ROLLBACK;`

---

## Step 4 - Read a Join Plan Bottom-Up

Run a join between pgbench_accounts and pgbench_branches:

```sql
EXPLAIN ANALYZE
SELECT a.aid, a.abalance, b.bbalance
FROM pgbench_accounts a
JOIN pgbench_branches b ON a.bid = b.bid
WHERE b.bid = 1;
```

**Expected:** A multi-node plan. Read it from the innermost (most indented) node outward:

```
                                        QUERY PLAN
------------------------------------------------------------------------------------------
 Nested Loop  (cost=... rows=... width=...) (actual time=... rows=... loops=1)
   ->  Index Scan using pgbench_branches_pkey on pgbench_branches b  (cost=... rows=1 ...) (actual time=... rows=1 loops=1)
         Index Cond: (bid = 1)
   ->  Seq Scan on pgbench_accounts a  (cost=... rows=... ...) (actual time=... rows=... loops=1)
         Filter: (bid = 1)
         Rows Removed by Filter: ...
```

Reading bottom-up:
1. The **innermost scan** on pgbench_branches uses the primary key index to find `bid = 1` - expected 1 row, got 1 row.
2. The **second scan** on pgbench_accounts filters for `bid = 1`.
3. The **Nested Loop** join combines the results from both scans.

> **Concept:** EXPLAIN plans are read from the most indented (deepest) node outward and upward. The deepest nodes execute first and feed data to their parent nodes. In a Nested Loop join, the outer table is scanned once, and for each row the inner table is scanned. In a Hash Join, the inner table is loaded into a hash table first, then the outer table is probed against it. In a Merge Join, both tables must be sorted on the join key.

---

## Step 5 - Interpret BUFFERS Output

Run EXPLAIN with ANALYZE and BUFFERS:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pgbench_accounts WHERE aid BETWEEN 1 AND 1000;
```

**Expected:** The plan now includes buffer usage statistics:

```
                                        QUERY PLAN
------------------------------------------------------------------------------------------
 Index Scan using pgbench_accounts_pkey on pgbench_accounts  (cost=... rows=... width=...)
   (actual time=... rows=1000 loops=1)
   Index Cond: ((aid >= 1) AND (aid <= 1000))
   Buffers: shared hit=XX read=YY
 Planning:
   Buffers: shared hit=ZZ
 Planning Time: ... ms
 Execution Time: ... ms
```

Key fields:
- `shared hit` - pages found in shared_buffers (no disk I/O needed)
- `shared read` - pages read from disk (or OS page cache) into shared_buffers
- `shared dirtied` - pages modified in shared_buffers (appears on write operations)

Run the same query a second time:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pgbench_accounts WHERE aid BETWEEN 1 AND 1000;
```

**Expected:** On the second run, `shared hit` should be higher and `shared read` should be lower (or zero) because the pages are now cached in shared_buffers.

> **Concept:** The BUFFERS output is the most direct way to measure I/O for a specific query. A high `shared read` means the data was not in the buffer cache - either the cache is too small or the data is accessed infrequently. A high `shared hit` means the data was cached - no disk I/O needed. When tuning queries, the goal is to maximize `shared hit` and minimize `shared read`. If a query consistently shows high `shared read`, consider whether the relevant index or table should be pre-warmed with `pg_prewarm`.

---

## Step 6 - Spot Estimated vs Actual Row Discrepancies

Run a query where the planner's estimate may differ from reality:

```sql
EXPLAIN ANALYZE SELECT * FROM pgbench_accounts WHERE abalance != 0;
```

**Expected:** Compare the `rows=` estimate with the `actual ... rows=` count. If the table statistics are stale or the data distribution is unusual, these numbers can differ significantly.

Now update the statistics and try again:

```sql
ANALYZE pgbench_accounts;
```

```sql
EXPLAIN ANALYZE SELECT * FROM pgbench_accounts WHERE abalance != 0;
```

**Expected:** After ANALYZE, the estimated rows should be closer to the actual rows because the planner has fresh statistics.

> **Concept:** The planner relies on statistics stored in `pg_statistic` (viewable via `pg_stats`) to estimate row counts. Stale statistics lead to bad estimates, which lead to bad plans - the planner might choose a sequential scan when an index scan would be faster, or vice versa. `ANALYZE` updates these statistics by sampling a fraction of the table. Autovacuum runs ANALYZE automatically, but after bulk loads or major data changes, running it manually ensures the planner has current information.

---

## Step 7 - Clean Up

Exit psql and the postgres user:

```sql
\q
```

```bash
exit
```

---

## Checkpoint

Before continuing, confirm:
- [ ] You triggered parser errors (syntax) and analyzer errors (missing table, type mismatch)
- [ ] You proved the rewriter expands views by examining the EXPLAIN output
- [ ] You documented which fields only appear in EXPLAIN ANALYZE (actual time, actual rows, loops, Planning Time, Execution Time)
- [ ] You read a join plan bottom-up and identified the scan type and join method
- [ ] You interpreted BUFFERS output (shared hit vs shared read) and observed caching effects
- [ ] You spotted estimated vs actual row discrepancies and fixed them with ANALYZE
- [ ] You know the danger of running EXPLAIN ANALYZE on destructive queries

---

**Next:** [05 - Connection Saturation](05-connection-saturation.md)
