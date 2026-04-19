# Exercise 04: Query Optimization

**Duration:** 35 minutes
**Objective:** Run EXPLAIN ANALYZE on four slow queries, identify the performance problem in each plan, and add the correct index to fix it.

**Prerequisites:** Build guide 05 (EXPLAIN) complete.

---

## Background

Every query plan tells a story. Seq Scan means "I had no index - I read every row". Large estimated vs actual row count gaps mean stale statistics. High cost nodes tell you where time is being spent. Your job is to read the plan, diagnose the cause, and apply the fix.

Connect before starting:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Setup: Create a Large Orders Table

The existing `orders` table may be small enough that sequential scans are actually faster. Create a larger table to make the problems visible:

```sql
CREATE TABLE IF NOT EXISTS orders_large AS SELECT * FROM orders;
```

Insert additional rows until you have at least 50,000 rows:

```sql
INSERT INTO orders_large (customer_id, status, total_amount, created_at)
SELECT (random() * 100 + 1)::INT,
       (ARRAY['pending', 'completed', 'shipped', 'cancelled'])[floor(random() * 4 + 1)],
       (random() * 500 + 10)::NUMERIC(10,2),
       now() - (random() * 365)::INT * INTERVAL '1 day'
FROM generate_series(1, 60000);
```

Update table statistics after the bulk insert:

```sql
ANALYZE orders_large;
```

Verify row count:

```sql
SELECT COUNT(*) FROM orders_large;
```

Expected output (yours will differ):

```
 count
-------
 60300
(1 row)
```

---

## Problem 1: Status Filter Without Index

This query finds all pending orders but has no index on `status`.

Run EXPLAIN ANALYZE first:

```sql
EXPLAIN ANALYZE SELECT * FROM orders_large WHERE status = 'pending';
```

Expected output (yours will differ):

```
 Seq Scan on orders_large  (cost=0.00..1820.00 rows=15000 width=60)
                            (actual time=0.030..18.500 rows=15075 loops=1)
   Filter: ((status)::text = 'pending'::text)
   Rows Removed by Filter: 45225
 Execution Time: 22.000 ms
```

**Your task:** Identify the problem, create the right index, and run EXPLAIN ANALYZE again to confirm improvement.

### Answer

The problem is a sequential scan - 45,225 rows discarded. Create a partial index on status since we frequently filter by a specific value:

```sql
CREATE INDEX idx_orders_large_status ON orders_large (status);
```

```sql
EXPLAIN ANALYZE SELECT * FROM orders_large WHERE status = 'pending';
```

Expected output (yours will differ):

```
 Bitmap Heap Scan on orders_large  (cost=200..800 rows=15000 width=60)
                                    (actual time=2.000..8.000 rows=15075 loops=1)
   Recheck Cond: ((status)::text = 'pending'::text)
   ->  Bitmap Index Scan on idx_orders_large_status  (cost=0.00..196 rows=15000 width=0)
         Index Cond: ((status)::text = 'pending'::text)
 Execution Time: 9.000 ms
```

The plan now uses the index. Execution time dropped significantly.

---

## Problem 2: Date Range Query Without Index

This query finds orders from the last 7 days:

```sql
EXPLAIN ANALYZE
SELECT order_id, customer_id, total_amount
FROM orders_large
WHERE created_at >= now() - INTERVAL '7 days';
```

Run the query. Look at whether an index scan is used.

**Your task:** Create the appropriate index and verify improvement.

### Answer

```sql
CREATE INDEX idx_orders_large_created_at ON orders_large (created_at);
```

```sql
EXPLAIN ANALYZE
SELECT order_id, customer_id, total_amount
FROM orders_large
WHERE created_at >= now() - INTERVAL '7 days';
```

---

## Problem 3: Missing Composite Index

This query filters by both `customer_id` and `status`:

```sql
EXPLAIN ANALYZE
SELECT order_id, total_amount
FROM orders_large
WHERE customer_id = 5 AND status = 'completed';
```

**Your task:** Determine whether separate indexes on each column or a composite index on both columns together would be better. Create the optimal index.

Hint: A composite index on `(customer_id, status)` can satisfy both predicates in a single index scan. The order of columns matters - put the higher-selectivity column first.

### Answer

```sql
CREATE INDEX idx_orders_large_cust_status ON orders_large (customer_id, status);
```

```sql
EXPLAIN ANALYZE
SELECT order_id, total_amount
FROM orders_large
WHERE customer_id = 5 AND status = 'completed';
```

A well-designed composite index will show an Index Scan with very few rows returned.

---

## Problem 4: Sort Without Supporting Index

This query returns the 20 highest-value orders and is run frequently by a reporting job:

```sql
EXPLAIN ANALYZE
SELECT order_id, customer_id, total_amount
FROM orders_large
ORDER BY total_amount DESC
LIMIT 20;
```

Look at the plan. If you see `Sort Method: external merge  Disk`, the sort is spilling to disk. Even an in-memory sort on 60,000 rows can be slow if called frequently.

**Your task:** Create an index that allows PostgreSQL to read rows in sorted order without sorting at all.

### Answer

```sql
CREATE INDEX idx_orders_large_amount_desc ON orders_large (total_amount DESC);
```

```sql
EXPLAIN ANALYZE
SELECT order_id, customer_id, total_amount
FROM orders_large
ORDER BY total_amount DESC
LIMIT 20;
```

Expected plan change: The sort step disappears and the planner uses the index to read the top 20 rows directly.

---

## Reflection Questions

Answer these without looking at the guides:

1. What does `Rows Removed by Filter` tell you in an EXPLAIN ANALYZE plan?
2. When would a sequential scan be FASTER than an index scan?
3. Why does the column order in a composite index matter?
4. What command do you run to force PostgreSQL to recalculate table statistics?

---

## Cleanup

```sql
DROP TABLE IF EXISTS orders_large;
```

```sql
\q
```

```bash
exit
```
