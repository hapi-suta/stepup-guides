# Build 05 - EXPLAIN ANALYZE and Query Optimization

**Time:** 45 minutes
**Goal:** Read query execution plans, identify common performance problems, and apply index-based and query-based optimizations.
**Prerequisites:** Aurora PostgreSQL cluster `devops-lab-cluster` running. psql access. Build 04 complete (pg_stat_statements enabled).

---

## Step 1 - Create Test Data

**On your local machine, connect to your Aurora database:**

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

Create tables with realistic data volumes:

```sql
CREATE TABLE IF NOT EXISTS customers (
    customer_id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    country TEXT NOT NULL,
    premium BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

```sql
CREATE TABLE IF NOT EXISTS orders (
    order_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    total NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

```sql
CREATE TABLE IF NOT EXISTS order_items (
    item_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_name TEXT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(10,2) NOT NULL
);
```

Load data:

```sql
INSERT INTO customers (name, email, country, premium)
SELECT
    'Customer ' || g,
    'customer_' || g || '@example.com',
    CASE (g % 5) WHEN 0 THEN 'US' WHEN 1 THEN 'UK' WHEN 2 THEN 'DE' WHEN 3 THEN 'FR' ELSE 'CA' END,
    (random() > 0.8)
FROM generate_series(1, 100000) g;
```

```sql
INSERT INTO orders (customer_id, status, total, created_at)
SELECT
    (random() * 100000 + 1)::BIGINT,
    CASE (random() * 4)::INT WHEN 0 THEN 'pending' WHEN 1 THEN 'processing' WHEN 2 THEN 'shipped' ELSE 'delivered' END,
    (random() * 1000 + 10)::NUMERIC(12,2),
    now() - (random() * interval '365 days')
FROM generate_series(1, 1000000);
```

```sql
INSERT INTO order_items (order_id, product_name, quantity, unit_price)
SELECT
    (random() * 1000000 + 1)::BIGINT,
    'Product ' || (random() * 1000)::INT,
    (random() * 5 + 1)::INT,
    (random() * 200 + 5)::NUMERIC(10,2)
FROM generate_series(1, 3000000);
```

Update statistics so the planner has accurate information:

```sql
ANALYZE customers, orders, order_items;
```

---

## Step 2 - Understand EXPLAIN Output

Run a basic EXPLAIN (without ANALYZE) to see the plan without executing:

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'pending';
```

Expected output (yours will differ):
```
                           QUERY PLAN
-----------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..22350.00 rows=250000 width=52)
   Filter: (status = 'pending'::text)
```

**Reading the plan:**

| Field | Meaning |
|-------|---------|
| Seq Scan | Full table scan - reads every row |
| cost=0.00..22350.00 | Startup cost..total cost (arbitrary units) |
| rows=250000 | Estimated rows to return |
| width=52 | Average row width in bytes |
| Filter | Condition applied during scan |

---

## Step 3 - Use EXPLAIN ANALYZE for Real Execution

EXPLAIN ANALYZE actually runs the query and shows real execution times:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT * FROM orders WHERE status = 'pending';
```

Each option explained:
- `ANALYZE`: Execute the query and show actual times and row counts.
- `BUFFERS`: Show buffer cache hit/miss information.
- `FORMAT TEXT`: Human-readable output (default). Other options: JSON, YAML, XML.

Expected output (yours will differ):
```
                                                QUERY PLAN
----------------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..22350.00 rows=250000 width=52) (actual time=0.032..145.678 rows=249123 loops=1)
   Filter: (status = 'pending'::text)
   Rows Removed by Filter: 750877
   Buffers: shared hit=12345 read=5678
 Planning Time: 0.085 ms
 Execution Time: 162.345 ms
```

**Reading the real execution data:**

| Field | Meaning |
|-------|---------|
| actual time=0.032..145.678 | Startup time..total time in milliseconds |
| rows=249123 | Actual rows returned (compare to estimated 250000) |
| loops=1 | How many times this node executed |
| Rows Removed by Filter: 750877 | Rows scanned but discarded by the filter |
| Buffers: shared hit=12345 | Pages found in shared_buffers (fast reads) |
| Buffers: shared read=5678 | Pages read from storage (slow reads) |
| Planning Time | Time spent planning the query |
| Execution Time | Total time executing the query |

---

## Step 4 - Fix Problem 1: Missing Index

The query above does a Seq Scan because there is no index on `orders.status`. Create one:

```sql
CREATE INDEX CONCURRENTLY idx_orders_status ON orders(status);
```

`CONCURRENTLY`: Creates the index without locking the table for writes. This takes longer but does not block production queries. Always use CONCURRENTLY on production tables.

Run the query again:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE status = 'pending';
```

Expected output (yours will differ):
```
                                                      QUERY PLAN
-----------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=2890.12..14567.89 rows=250000 width=52) (actual time=12.345..65.432 rows=249123 loops=1)
   Recheck Cond: (status = 'pending'::text)
   Heap Blocks: exact=10234
   Buffers: shared hit=11000 read=234
   ->  Bitmap Index Scan on idx_orders_status  (cost=0.00..2827.62 rows=250000 width=0) (actual time=11.234..11.234 rows=249123 loops=1)
         Index Cond: (status = 'pending'::text)
         Buffers: shared hit=700
 Execution Time: 78.901 ms
```

The plan changed from Seq Scan to Bitmap Heap Scan. The execution time dropped from ~162ms to ~79ms. The index is helping.

However, since `status = 'pending'` matches 25% of the table, the improvement is moderate. Indexes help most when they are selective (matching a small percentage of rows).

---

## Step 5 - Fix Problem 2: Partial Index for Better Selectivity

If you only query pending orders frequently, a partial index is more efficient:

```sql
CREATE INDEX CONCURRENTLY idx_orders_pending ON orders(created_at)
WHERE status = 'pending';
```

This index only includes rows where status is 'pending', making it much smaller.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE status = 'pending'
  AND created_at > now() - interval '7 days';
```

Expected output (yours will differ):
```
                                                      QUERY PLAN
-----------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_orders_pending on orders  (cost=0.42..1234.56 rows=4800 width=52) (actual time=0.025..2.345 rows=4762 loops=1)
   Index Cond: (created_at > ...)
   Buffers: shared hit=150
 Execution Time: 3.456 ms
```

The query now uses an Index Scan (the most efficient scan type) and completes in ~3ms instead of ~162ms. That is a 50x improvement.

---

## Step 6 - Fix Problem 3: Sort Spills to Disk

Run a query that sorts a large result set:

```sql
SET work_mem = '4MB';
```

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, sum(total) AS total_spent
FROM orders
GROUP BY customer_id
ORDER BY total_spent DESC
LIMIT 100;
```

Look for `Sort Method: external merge Disk:` in the output. This means the sort exceeded work_mem and spilled to temp files on disk.

Expected output (yours will differ):
```
                                                      QUERY PLAN
-----------------------------------------------------------------------------------------------------------------------
 Limit  (cost=... rows=100 width=40) (actual time=1234.567..1234.589 rows=100 loops=1)
   ->  Sort  (cost=... rows=100000 width=40) (actual time=1234.565..1234.578 rows=100 loops=1)
         Sort Key: (sum(total)) DESC
         Sort Method: external merge  Disk: 3456kB
         ->  HashAggregate  (cost=... rows=100000 width=40) (actual time=987.654..1123.456 rows=99876 loops=1)
               ...
```

Fix by increasing work_mem for this session:

```sql
SET work_mem = '64MB';
```

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, sum(total) AS total_spent
FROM orders
GROUP BY customer_id
ORDER BY total_spent DESC
LIMIT 100;
```

Expected output (yours will differ):
```
         Sort Method: quicksort  Memory: 8456kB
```

The sort now happens in memory (`quicksort Memory: 8456kB`) instead of on disk. Execution time drops significantly.

Reset work_mem to the default:

```sql
RESET work_mem;
```

---

## Step 7 - Fix Problem 4: Missing JOIN Index

Run a join query without an index on the join column:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, count(oi.item_id), sum(oi.unit_price * oi.quantity)
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.created_at > now() - interval '7 days'
GROUP BY o.order_id
ORDER BY sum(oi.unit_price * oi.quantity) DESC
LIMIT 20;
```

Without an index on `order_items.order_id`, PostgreSQL must scan the entire order_items table for each matching order. Look for `Seq Scan on order_items` or a large `Hash Join` in the plan.

Fix it:

```sql
CREATE INDEX CONCURRENTLY idx_order_items_order_id ON order_items(order_id);
```

Run the query again and compare execution times. You should see a Nested Loop with Index Scan replacing the Hash Join.

---

## Step 8 - Fix Problem 5: Correlated Subquery to JOIN

Correlated subqueries execute once per row in the outer query. This is extremely slow on large tables:

```sql
EXPLAIN (ANALYZE)
SELECT c.customer_id, c.name,
    (SELECT count(*) FROM orders o WHERE o.customer_id = c.customer_id) AS order_count
FROM customers c
WHERE c.country = 'US'
LIMIT 100;
```

Look for `SubPlan` in the output - this indicates a correlated subquery running once per customer row.

Rewrite as a JOIN:

```sql
EXPLAIN (ANALYZE)
SELECT c.customer_id, c.name, count(o.order_id) AS order_count
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE c.country = 'US'
GROUP BY c.customer_id, c.name
LIMIT 100;
```

The JOIN version processes the data in a single pass instead of running a subquery for each row.

---

## Step 9 - The EXPLAIN Checklist

When reading any query plan, check for these red flags:

| Red Flag | What It Means | Fix |
|----------|--------------|-----|
| Seq Scan on a large table | Full table scan | Add an index on the filter/join column |
| Rows Removed by Filter is very high | Index not selective enough | Add a partial index or composite index |
| Sort Method: external merge Disk | Sort exceeded work_mem | Increase work_mem or reduce result set |
| Nested Loop with Seq Scan inner | For each outer row, scanning entire inner table | Add index on the join column |
| Hash Join with large hash table | Join building a large hash table | Ensure join columns are indexed |
| Actual rows >> Estimated rows | Planner statistics are stale | Run ANALYZE on the table |
| Actual rows << Estimated rows | Planner overestimates cardinality | Run ANALYZE, check correlation |
| Buffers: read is much larger than hit | Data not cached | Check shared_buffers, consider larger instance |

---

## Cleanup

```sql
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
```

---

## Summary

You have:
- Learned to read EXPLAIN and EXPLAIN ANALYZE output
- Created regular indexes, partial indexes, and join indexes
- Fixed sort spills by adjusting work_mem
- Rewritten a correlated subquery as a JOIN
- Built a checklist for reading query plans

EXPLAIN ANALYZE is the single most powerful diagnostic tool for query optimization. Use it before and after every change to measure the impact.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Seq Scan | Sequential scan - reads every row in the table |
| Index Scan | Uses an index to find matching rows directly |
| Bitmap Heap Scan | Uses an index to build a bitmap of matching pages, then reads those pages |
| Nested Loop | For each row in outer, scan inner (fast with index, slow without) |
| Hash Join | Build hash table from smaller table, probe with larger table |
| Merge Join | Both sides sorted, merge like a zipper |
| CONCURRENTLY | Create index without locking table for writes |
| Partial index | Index with a WHERE clause - indexes only matching rows |
| work_mem | Memory per sort/hash operation - excess spills to disk |
| external merge Disk | Sort spilled to temporary files because work_mem was too small |
