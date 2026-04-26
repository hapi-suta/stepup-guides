# Guide 01 - EXPLAIN and EXPLAIN ANALYZE

Learn how to read PostgreSQL query execution plans to understand what the database is actually doing when it runs your SQL.

**Server:** NODE1 only

---

## What You Will Learn

- The difference between EXPLAIN and EXPLAIN ANALYZE
- How to read a query plan: costs, rows, width
- The six most common plan node types
- How to use BUFFERS and FORMAT JSON for deeper analysis

---

## 1. Connect to the Server

SSH into NODE1 as ec2-user.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

Switch to the postgres user.

```
sudo -iu postgres
```

Connect to the stepup_store database.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Expected output (yours will differ):

```
psql (16.x)
Type "help" for help.

stepup_store=#
```

---

## 2. EXPLAIN vs EXPLAIN ANALYZE

### EXPLAIN (estimates only - does NOT run the query)

```sql
EXPLAIN SELECT * FROM orders WHERE customer_id = 5;
```

Expected output (yours will differ):

```
                        QUERY PLAN
----------------------------------------------------------
 Seq Scan on orders  (cost=0.00..1093.00 rows=5 width=43)
   Filter: (customer_id = 5)
(2 rows)
```

EXPLAIN shows PostgreSQL's **plan** without executing the query. It uses table statistics to estimate costs and row counts.

> **Concept - Cost Units**: Costs are not milliseconds. They are arbitrary units calibrated so that a sequential page read costs 1.0. `cost=0.00..1093.00` means startup cost (time before first row returned) is 0.00 and total cost is 1093.00. Lower total cost = PostgreSQL thinks this plan is faster.

### EXPLAIN ANALYZE (runs the query, shows actual times)

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 5;
```

Expected output (yours will differ):

```
                                                QUERY PLAN
----------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..1093.00 rows=5 width=43) (actual time=0.381..3.329 rows=7 loops=1)
   Filter: (customer_id = 5)
   Rows Removed by Filter: 49993
 Planning Time: 0.028 ms
 Execution Time: 3.340 ms
(5 rows)
```

EXPLAIN ANALYZE actually **executes** the query and reports real timings. The `actual time` shows real milliseconds. `loops=1` means this node ran once. `Rows Removed by Filter` shows how many rows were scanned but discarded.

> **Concept - Estimates vs Actuals**: When estimated rows and actual rows differ widely (e.g., estimated 1, actual 3000), PostgreSQL's statistics are stale. Run `ANALYZE orders;` to refresh them. Bad estimates lead to bad plan choices.

---

## 3. Reading Cost Numbers

Every plan node has the format: `(cost=startup..total rows=N width=W)`

- **startup cost** - cost before this node can return its first row (sorting must complete before returning anything)
- **total cost** - estimated cost to return all rows
- **rows** - estimated number of rows this node will return
- **width** - estimated average row size in bytes

```sql
EXPLAIN SELECT o.order_id, c.email
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.total_amount > 100;
```

Expected output (yours will differ):

```
                                  QUERY PLAN
------------------------------------------------------------------------------
 Hash Join  (cost=339.00..1539.06 rows=40766 width=24)
   Hash Cond: (o.customer_id = c.customer_id)
   ->  Seq Scan on orders o  (cost=0.00..1093.00 rows=40766 width=8)
         Filter: (total_amount > '100'::numeric)
   ->  Hash  (cost=214.00..214.00 rows=10000 width=24)
         ->  Seq Scan on customers c  (cost=0.00..214.00 rows=10000 width=24)
(6 rows)
```

Read plans **from inside out, bottom to top**. The innermost (most indented) nodes execute first.

---

## 4. The Six Plan Node Types

### Seq Scan - reads every row in the table

```sql
EXPLAIN SELECT * FROM products;
```

Expected output:

```
                       QUERY PLAN
----------------------------------------------------------
 Seq Scan on products  (cost=0.00..1.50 rows=50 width=28)
(1 row)
```

A Seq Scan is fine for small tables or when fetching most rows. On large tables with selective filters, it signals a missing index.

### Index Scan - uses a B-tree index, follows heap pointers

```sql
EXPLAIN SELECT * FROM customers WHERE customer_id = 42;
```

Expected output (yours will differ):

```
                                   QUERY PLAN
---------------------------------------------------------------------------------
 Index Scan using customers_pkey on customers  (cost=0.29..8.30 rows=1 width=57)
   Index Cond: (customer_id = 42)
(2 rows)
```

Index Scan reads the index first to find the row location, then fetches the actual row from the heap. Best for highly selective queries (few rows returned).

### Bitmap Heap Scan - batches index lookups, then fetches heap pages

First, create an index on total_amount so the planner has an index to work with.

```sql
CREATE INDEX orders_total_amount_idx ON orders(total_amount);
```

Expected output:

```
CREATE INDEX
```

Now run a range query.

```sql
EXPLAIN SELECT * FROM orders WHERE total_amount BETWEEN 50 AND 200;
```

Expected output (yours will differ):

```
                                         QUERY PLAN
--------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=321.43..1013.53 rows=14940 width=43)
   Recheck Cond: ((total_amount >= '50'::numeric) AND (total_amount <= '200'::numeric))
   ->  Bitmap Index Scan on orders_total_amount_idx  (cost=0.00..317.69 rows=14940 width=0)
         Index Cond: ((total_amount >= '50'::numeric) AND (total_amount <= '200'::numeric))
(4 rows)
```

> **Concept - Bitmap Scan**: PostgreSQL first scans the index to build a bitmap of which heap pages contain matching rows. Then it fetches those pages in page order, which is more I/O-efficient than random heap access when many rows match. You often see a `Recheck Cond` because the bitmap can be lossy at high row counts.

### Hash Join - builds a hash table from the smaller relation

```sql
EXPLAIN SELECT p.name, SUM(oi.quantity)
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.name;
```

Expected output (yours will differ):

```
                                    QUERY PLAN
----------------------------------------------------------------------------------
 HashAggregate  (cost=3635.25..3635.59 rows=34 width=22)
   Group Key: p.name
   ->  Hash Join  (cost=2.12..2885.25 rows=150000 width=18)
         Hash Cond: (oi.product_id = p.product_id)
         ->  Seq Scan on order_items oi  (cost=0.00..2456.00 rows=150000 width=8)
         ->  Hash  (cost=1.50..1.50 rows=50 width=18)
               ->  Seq Scan on products p  (cost=0.00..1.50 rows=50 width=18)
(7 rows)
```

Hash Join hashes the smaller table (products, 50 rows) into memory, then probes the hash for each row from the larger table. Efficient when the smaller table fits in `work_mem`.

### Nested Loop - for each outer row, scan the inner relation

First, create an index on orders.customer_id so the planner can use it for the inner loop.

```sql
CREATE INDEX orders_customer_id_idx ON orders(customer_id);
```

Expected output:

```
CREATE INDEX
```

```sql
EXPLAIN SELECT c.email, o.total_amount
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
WHERE c.customer_id = 10;
```

Expected output (yours will differ):

```
                                        QUERY PLAN
-------------------------------------------------------------------------------------------
 Nested Loop  (cost=4.61..31.19 rows=5 width=26)
   ->  Index Scan using customers_pkey on customers c  (cost=0.29..8.30 rows=1 width=24)
         Index Cond: (customer_id = 10)
   ->  Bitmap Heap Scan on orders o  (cost=4.33..22.84 rows=5 width=10)
         Recheck Cond: (customer_id = 10)
         ->  Bitmap Index Scan on orders_customer_id_idx  (cost=0.00..4.33 rows=5 width=0)
               Index Cond: (customer_id = 10)
(7 rows)
```

Nested Loop is efficient when the outer relation is tiny (like one customer). It executes the inner scan once per outer row.

### Merge Join - sorts both sides and merges them

With indexes on both sides of the join key, PostgreSQL can use a Merge Join - reading both indexes in order and merging the results.

```sql
EXPLAIN SELECT c.email, o.order_id
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
ORDER BY c.customer_id;
```

The planner may choose Hash Join instead of Merge Join at this data size. To see a Merge Join for learning purposes, temporarily disable Hash Join.

```sql
SET enable_hashjoin = off;
SET enable_nestloop = off;
```

```sql
EXPLAIN SELECT c.email, o.order_id
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
ORDER BY c.customer_id;
```

Expected output (yours will differ):

```
                                             QUERY PLAN
----------------------------------------------------------------------------------------------------
 Merge Join  (cost=0.57..3955.97 rows=50000 width=28)
   Merge Cond: (c.customer_id = o.customer_id)
   ->  Index Scan using customers_pkey on customers c  (cost=0.29..387.69 rows=10000 width=24)
   ->  Index Scan using orders_customer_id_idx on orders o  (cost=0.29..2918.28 rows=50000 width=8)
(4 rows)
```

Merge Join requires both inputs sorted on the join key. It can avoid a sort if an index already provides the order. Notice both sides use Index Scan, which gives pre-sorted data.

Reset the planner settings.

```sql
RESET enable_hashjoin;
RESET enable_nestloop;
```

---

## 5. EXPLAIN ANALYZE with BUFFERS

BUFFERS shows cache hit and miss counts - critical for diagnosing I/O performance.

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE customer_id = 5;
```

Expected output (yours will differ):

```
                                                QUERY PLAN
----------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..1093.00 rows=5 width=43) (actual time=0.333..3.018 rows=7 loops=1)
   Filter: (customer_id = 5)
   Rows Removed by Filter: 49993
   Buffers: shared hit=468
 Planning Time: 0.025 ms
 Execution Time: 3.028 ms
(6 rows)
```

- `shared hit` - pages read from shared_buffers (fast, no disk I/O)
- `shared read` - pages read from disk (slow)
- `local hit/read` - temporary table pages
- `temp written` - spill to disk during sorts/hashes (very slow)

> **Concept - Buffers**: If you see `shared read` instead of `shared hit`, PostgreSQL is going to disk for that data. High `shared read` counts mean your `shared_buffers` may be too small for your working set, or the data was recently evicted. Run the same query twice - the second run should show all `hit` if the data fits in cache.

---

## 6. EXPLAIN with FORMAT JSON

JSON format gives you the full plan tree as structured data - useful for tooling and deep analysis.

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM orders WHERE customer_id = 5;
```

Expected output (yours will differ):

```
                    QUERY PLAN
-------------------------------------------
 [                                        +
   {                                      +
     "Plan": {                            +
       "Node Type": "Seq Scan",           +
       "Relation Name": "orders",         +
       "Alias": "orders",                 +
       "Startup Cost": 0.00,              +
       "Total Cost": 1093.00,            +
       "Plan Rows": 5,                    +
       "Plan Width": 43,                  +
       "Actual Startup Time": 0.015,      +
       ...
```

The JSON format is machine-readable. Tools like `explain.depesz.com` and `pganalyze` accept this format to render visual plans.

---

## 7. Practical: Compare Two Plans

You already created `orders_customer_id_idx` in Section 4. Let's see how it changes a query plan.

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 99;
```

Expected output (yours will differ):

```
                                                          QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=4.33..22.84 rows=5 width=43) (actual time=0.012..0.017 rows=5 loops=1)
   Recheck Cond: (customer_id = 99)
   Heap Blocks: exact=5
   ->  Bitmap Index Scan on orders_customer_id_idx  (cost=0.00..4.33 rows=5 width=0) (actual time=0.008..0.008 rows=5 loops=1)
         Index Cond: (customer_id = 99)
 Planning Time: 0.040 ms
 Execution Time: 0.030 ms
(7 rows)
```

Compare this to the Seq Scan you saw in Section 2 (cost=1093.00, ~3ms). With the index, the cost dropped to 22.84 and execution time is under 0.1ms.

Now clean up the indexes created during this lab. Guide 02 will create its own indexes.

```sql
DROP INDEX orders_total_amount_idx;
```

```sql
DROP INDEX orders_customer_id_idx;
```

```
\q
```

```
exit
```

---

## Checkpoint

By the end of this guide you should be able to:

- [ ] Explain the difference between EXPLAIN and EXPLAIN ANALYZE
- [ ] Read the cost, rows, and width fields in a plan node
- [ ] Identify Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join, Nested Loop, and Merge Join
- [ ] Use EXPLAIN (ANALYZE, BUFFERS) to see cache hit/miss counts
- [ ] Use FORMAT JSON to get machine-readable plan output

---

**Proceed to:** [Guide 02 - Index Strategies](./02-index-strategies.md)
