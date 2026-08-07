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

The existing `orders` table (50 rows) is far too small for a sequential scan to ever look slow. Create a larger table to make the problems visible:

```sql
CREATE TABLE IF NOT EXISTS orders_large AS SELECT * FROM orders;
```

Insert additional rows until you have well over 50,000 rows. This synthetic batch uses its own random status set (including `completed`, which does not exist in the real `orders` table) purely to get a realistic spread for the performance exercises below:

```sql
INSERT INTO orders_large (customer_id, status, total_amount, order_date)
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

Expected output (yours will differ slightly in the last digits if you re-run the INSERT, but should be 50 + 60000):

```
 count
-------
 60050
(1 row)
```

---

## Problem 1: Status Filter Without Index

This query finds all pending orders but has no index on `status`.

Run EXPLAIN ANALYZE first:

```sql
EXPLAIN ANALYZE SELECT * FROM orders_large WHERE status = 'pending';
```

Expected output (yours will differ in exact row counts and timings - `status` is assigned randomly):

```
 Seq Scan on orders_large  (cost=0.00..1223.62 rows=15004 width=31) (actual time=0.007..6.765 rows=15035 loops=1)
   Filter: ((status)::text = 'pending'::text)
   Rows Removed by Filter: 45015
 Planning Time: 0.089 ms
 Execution Time: 7.263 ms
```

**Your task:** Identify the problem, create the right index, and run EXPLAIN ANALYZE again to confirm improvement.

### Answer

The problem is a sequential scan - roughly 45,000 rows discarded to find roughly 15,000 matches. Create an index on `status` since we frequently filter by a specific value:

```sql
CREATE INDEX idx_orders_large_status ON orders_large (status);
```

```sql
EXPLAIN ANALYZE SELECT * FROM orders_large WHERE status = 'pending';
```

Expected output (yours will differ):

```
 Bitmap Heap Scan on orders_large  (cost=172.57..833.12 rows=15004 width=31) (actual time=0.541..2.914 rows=15035 loops=1)
   Recheck Cond: ((status)::text = 'pending'::text)
   Heap Blocks: exact=473
   ->  Bitmap Index Scan on idx_orders_large_status  (cost=0.00..168.82 rows=15004 width=0) (actual time=0.485..0.485 rows=15035 loops=1)
         Index Cond: ((status)::text = 'pending'::text)
 Planning Time: 0.161 ms
 Execution Time: 3.390 ms
```

The plan now uses `Bitmap Index Scan` on the new index (PostgreSQL chooses a bitmap scan rather than a plain index scan because ~25% of the table matches - a plain index scan would mean too many random heap lookups). Execution time roughly halved in this run - the gain grows with table size and with more selective filters.

---

## Problem 2: Date Range Query Without Index

This query finds orders from the last 7 days:

```sql
EXPLAIN ANALYZE
SELECT order_id, customer_id, total_amount
FROM orders_large
WHERE order_date >= now() - INTERVAL '7 days';
```

Expected output (yours will differ):

```
 Seq Scan on orders_large  (cost=0.00..1523.88 rows=1230 width=14) (actual time=0.011..13.758 rows=1089 loops=1)
   Filter: (order_date >= (now() - '7 days'::interval))
   Rows Removed by Filter: 58961
 Planning Time: 0.069 ms
 Execution Time: 13.802 ms
```

Run the query. Look at whether an index scan is used - it is not, because there is no index on `order_date` yet.

**Your task:** Create the appropriate index and verify improvement.

### Answer

```sql
CREATE INDEX idx_orders_large_order_date ON orders_large (order_date);
```

```sql
EXPLAIN ANALYZE
SELECT order_id, customer_id, total_amount
FROM orders_large
WHERE order_date >= now() - INTERVAL '7 days';
```

Expected output (yours will differ):

```
 Bitmap Heap Scan on orders_large  (cost=17.83..512.35 rows=1230 width=14) (actual time=0.114..0.744 rows=1089 loops=1)
   Recheck Cond: (order_date >= (now() - '7 days'::interval))
   Heap Blocks: exact=426
   ->  Bitmap Index Scan on idx_orders_large_order_date  (cost=0.00..17.52 rows=1230 width=0) (actual time=0.068..0.138 rows=1089 loops=1)
         Index Cond: (order_date >= (now() - '7 days'::interval))
 Planning Time: 0.221 ms
 Execution Time: 0.813 ms
```

Execution time dropped from double digits to under a millisecond in this run, because the date-range filter matches under 2% of the table - a highly selective filter is exactly where an index pays off most.

---

## Problem 3: Missing Composite Index

This query filters by both `customer_id` and `status`:

```sql
EXPLAIN ANALYZE
SELECT order_id, total_amount
FROM orders_large
WHERE customer_id = 5 AND status = 'completed';
```

Expected output (yours will differ):

```
 Bitmap Heap Scan on orders_large  (cost=170.05..870.50 rows=153 width=10) (actual time=0.611..2.777 rows=146 loops=1)
   Recheck Cond: ((status)::text = 'completed'::text)
   Filter: (customer_id = 5)
   Rows Removed by Filter: 14937
   Heap Blocks: exact=473
   ->  Bitmap Index Scan on idx_orders_large_status  (cost=0.00..170.01 rows=15163 width=0) (actual time=0.530..0.530 rows=15083 loops=1)
         Index Cond: ((status)::text = 'completed'::text)
 Planning Time: 0.071 ms
 Execution Time: 2.796 ms
```

Notice the plan reuses the single-column `status` index from Problem 1, then applies `customer_id = 5` as a plain `Filter` afterward - it still has to fetch and discard almost 15,000 rows that matched on status but not on customer.

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

Expected output (yours will differ):

```
 Bitmap Heap Scan on orders_large  (cost=5.86..326.96 rows=153 width=10) (actual time=0.053..0.182 rows=146 loops=1)
   Recheck Cond: ((customer_id = 5) AND ((status)::text = 'completed'::text))
   Heap Blocks: exact=127
   ->  Bitmap Index Scan on idx_orders_large_cust_status  (cost=0.00..5.82 rows=153 width=0) (actual time=0.037..0.037 rows=146 loops=1)
         Index Cond: ((customer_id = 5) AND ((status)::text = 'completed'::text))
 Planning Time: 0.157 ms
 Execution Time: 0.223 ms
```

Both predicates are now satisfied by a single `Bitmap Index Scan` against the composite index (`Recheck Cond` shows both conditions), and the cost dropped by roughly 30x compared to Problem 3's first plan.

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

Expected output (yours will differ):

```
 Limit  (cost=2671.41..2671.46 rows=20 width=14) (actual time=17.249..17.252 rows=20 loops=1)
   ->  Sort  (cost=2671.41..2821.53 rows=60050 width=14) (actual time=17.248..17.249 rows=20 loops=1)
         Sort Key: total_amount DESC
         Sort Method: top-N heapsort  Memory: 26kB
         ->  Seq Scan on orders_large  (cost=0.00..1073.50 rows=60050 width=14) (actual time=0.006..7.159 rows=60050 loops=1)
 Planning Time: 0.064 ms
 Execution Time: 17.264 ms
```

Look at the plan. `Sort Method: top-N heapsort` means PostgreSQL is smart enough to keep only the running top 20 in memory rather than sorting all 60,050 rows fully - but it still has to Seq Scan the entire table first to feed the sort. If you saw `Sort Method: external merge  Disk` instead, the sort would be spilling to disk - even worse.

**Your task:** Create an index that allows PostgreSQL to read rows in sorted order without scanning and sorting the whole table.

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

Expected output (yours will differ):

```
 Limit  (cost=0.29..1.44 rows=20 width=14) (actual time=0.029..0.036 rows=20 loops=1)
   ->  Index Scan using idx_orders_large_amount_desc on orders_large  (cost=0.29..3461.04 rows=60050 width=14) (actual time=0.028..0.033 rows=20 loops=1)
 Planning Time: 0.194 ms
 Execution Time: 0.046 ms
```

The `Sort` step disappears entirely. PostgreSQL walks the index in its existing sorted order and stops after 20 rows - it never scans or sorts the other 60,030. Execution time dropped from 17ms to under 0.05ms in this run - roughly 350x faster - because the query no longer touches most of the table at all.

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
