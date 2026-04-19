# Exercise 03: Prove Partition Pruning

**Duration:** 25 minutes
**Objective:** Write queries that trigger partition pruning, prove it with EXPLAIN ANALYZE, measure the actual performance difference, and understand when pruning fails.

**Prerequisites:**
- `orders_partitioned` with data loaded (Exercise 02 complete)
- ANALYZE has been run on `orders_partitioned`

---

## Background

Partition pruning is the planner's ability to skip partitions that cannot contain rows matching your WHERE clause. It is the primary reason partitioned tables outperform non-partitioned tables for date-range queries. In this exercise you learn to read EXPLAIN output to confirm pruning is happening - and diagnose when it is not.

---

## Step 1: Baseline - Query Without Pruning

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

First, confirm pruning is enabled (it should be by default):

```sql
SHOW enable_partition_pruning;
```

Expected output:

```
 enable_partition_pruning
--------------------------
 on
(1 row)
```

Run a query with NO partition key filter to see what a full-table scan looks like across all partitions:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT COUNT(*) FROM orders_partitioned
WHERE status = 'completed';
```

Expected output (yours will differ - count the number of partitions in the plan):

```
                                     QUERY PLAN
------------------------------------------------------------------------------------
 Finalize Aggregate  (cost=... actual time=... rows=1 loops=1)
   ->  Gather  (cost=... actual time=... rows=... loops=1)
         ->  Partial Aggregate  (cost=... actual time=...)
               ->  Append  (cost=... actual time=...)
                     ->  Seq Scan on orders_2023_01  (cost=... actual time=...)
                           Filter: ((status)::text = 'completed'::text)
                     ->  Seq Scan on orders_2023_02  (cost=... actual time=...)
                     ...
                     ->  Seq Scan on orders_2025_06  (cost=... actual time=...)
 Planning Time: 4.231 ms
 Execution Time: 892.341 ms
```

Count the "Seq Scan on orders_..." lines - there should be one per partition (27 or more). No pruning happened because `status` is not the partition key.

---

## Step 2: Single-Month Pruning

Run a query filtering on exactly one month:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT COUNT(*) FROM orders_partitioned
WHERE order_date >= '2024-06-01' AND order_date < '2024-07-01';
```

Expected output (yours will differ):

```
                                  QUERY PLAN
--------------------------------------------------------------------------------
 Aggregate  (cost=... actual time=... rows=1 loops=1)
   Buffers: shared hit=...
   ->  Seq Scan on orders_2024_06 orders_partitioned_1  (cost=... actual time=...)
         Filter: ((order_date >= '2024-06-01'::date) AND (order_date < '2024-07-01'::date))
         Rows Removed by Filter: 0
         Buffers: shared hit=...
 Planning Time: 2.841 ms
 Execution Time: 8.123 ms
```

Only `orders_2024_06` appears. All other partitions were pruned. Execution time dropped from ~892ms to ~8ms - more than 100x faster for this query shape.

---

## Step 3: Multi-Month Pruning

Run a query that spans a quarter (3 months):

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT SUM(total_amount) FROM orders_partitioned
WHERE order_date >= '2024-10-01' AND order_date < '2025-01-01';
```

Expected output (yours will differ):

```
                                  QUERY PLAN
--------------------------------------------------------------------------------
 Aggregate  (cost=... actual time=... rows=1 loops=1)
   ->  Append  (cost=... actual time=...)
         ->  Seq Scan on orders_2024_10  (cost=... actual time=...)
         ->  Seq Scan on orders_2024_11  (cost=... actual time=...)
         ->  Seq Scan on orders_2024_12  (cost=... actual time=...)
 Planning Time: 3.102 ms
 Execution Time: 23.441 ms
```

Only 3 partitions (October, November, December 2024) appear. The other 24+ partitions were pruned.

---

## Step 4: Pruning With a Constant Expression

PostgreSQL can evaluate simple expressions at planning time and use them for pruning:

```sql
EXPLAIN
SELECT * FROM orders_partitioned
WHERE order_date = CURRENT_DATE;
```

Expected output (yours will differ):

```
                        QUERY PLAN
------------------------------------------------------------------
 Seq Scan on orders_2025_04 orders_partitioned_1
   Filter: (order_date = CURRENT_DATE)
(2 rows)
```

Only the current month's partition appears because PostgreSQL evaluates `CURRENT_DATE` at planning time and prunes based on the result.

Now test with a function that PostgreSQL cannot evaluate at plan time:

```sql
EXPLAIN
SELECT * FROM orders_partitioned
WHERE order_date = (SELECT MAX(order_date) FROM orders);
```

Expected output (yours will differ):

```
                                 QUERY PLAN
---------------------------------------------------------------------------
 Append  (cost=...)
   ->  Seq Scan on orders_2023_01
   ->  Seq Scan on orders_2023_02
   ...
   ->  Seq Scan on orders_2025_06
(30 rows)
```

All partitions are scanned. The subquery `(SELECT MAX(order_date) FROM orders)` is not a constant at plan time - the planner cannot evaluate it until execution. This is a common pruning failure. Rewrite to pass the value as a parameter or literal instead.

> **Concept - Runtime pruning vs plan-time pruning**
> PostgreSQL has two pruning stages. Plan-time pruning eliminates partitions using constant values in the WHERE clause (literals, CURRENT_DATE, stable functions). This shows in EXPLAIN as fewer partitions listed. Runtime pruning (added in PG11) can eliminate partitions during execution when the actual values become known - for example, in a loop or when the WHERE clause uses a parameter. Use `EXPLAIN (ANALYZE)` instead of plain `EXPLAIN` to see runtime pruning in action, because runtime pruning does not show up in plan-time EXPLAIN output.

---

## Step 5: Pruning Failure Patterns

Document the patterns that defeat pruning so you can avoid them.

**Pattern 1: Casting the partition key**

```sql
EXPLAIN
SELECT * FROM orders_partitioned
WHERE EXTRACT(YEAR FROM order_date) = 2024;
```

Expected output (yours will differ):

```
 Append  (cost=...)
   ->  Seq Scan on orders_2023_01
   ...
   ->  Seq Scan on orders_2025_06
```

All partitions scanned. When you wrap the partition key in a function (`EXTRACT`), PostgreSQL cannot use the partition bounds for pruning. Rewrite as:

```sql
EXPLAIN
SELECT * FROM orders_partitioned
WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01';
```

Expected output (yours will differ):

```
 Append  (cost=...)
   ->  Seq Scan on orders_2024_01
   ->  Seq Scan on orders_2024_02
   ...
   ->  Seq Scan on orders_2024_12
```

Now only the 12 months of 2024 appear.

**Pattern 2: OR conditions spanning multiple partitions**

```sql
EXPLAIN
SELECT * FROM orders_partitioned
WHERE order_date = '2024-01-15' OR order_date = '2025-03-10';
```

Expected output (yours will differ):

```
 Append  (cost=...)
   ->  Seq Scan on orders_2024_01
         Filter: ...
   ->  Seq Scan on orders_2025_03
         Filter: ...
```

Two partitions are scanned - this is correct and expected. OR conditions with constants on the partition key prune to only the relevant partitions.

---

## Step 6: Side-by-Side Performance Comparison

Compare the same query against the non-partitioned `orders` table and the partitioned table. Time both:

```sql
\timing on
```

Query against `orders` (non-partitioned):

```sql
SELECT SUM(total_amount)
FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01';
```

Expected output (yours will differ):

```
     sum
-------------
 45832109.23
(1 row)

Time: 312.451 ms
```

Same query against `orders_partitioned`:

```sql
SELECT SUM(total_amount)
FROM orders_partitioned
WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01';
```

Expected output (yours will differ):

```
     sum
-------------
 45832109.23
(1 row)

Time: 34.123 ms
```

The sums match (data integrity confirmed). The partitioned query is roughly 9x faster because it scanned only 12 partitions instead of the entire table.

Turn timing off:

```sql
\timing off
```

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## Checkpoint

- [ ] You can read EXPLAIN output to count how many partitions were scanned vs pruned
- [ ] You understand that pruning requires the WHERE clause to filter on the partition key column directly (no function wrapping)
- [ ] You can demonstrate single-month, multi-month, and range-based pruning with EXPLAIN ANALYZE
- [ ] You know that `CURRENT_DATE` is evaluated at plan time and enables pruning, while a subquery is not
- [ ] You can identify the four common pruning failure patterns: function wrapping, subquery values, non-partition-key filters, and runtime-only values
- [ ] You measured the actual execution time difference between partitioned and non-partitioned for the same query
