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
-----------------------------------------------------------
 Seq Scan on orders  (cost=0.00..12.50 rows=1 width=72)
   Filter: (customer_id = 5)
(2 rows)
```

EXPLAIN shows PostgreSQL's **plan** without executing the query. It uses table statistics to estimate costs and row counts.

> **Concept - Cost Units**: Costs are not milliseconds. They are arbitrary units calibrated so that a sequential page read costs 1.0. `cost=0.00..12.50` means startup cost (time before first row returned) is 0.00 and total cost is 12.50. Lower total cost = PostgreSQL thinks this plan is faster.

### EXPLAIN ANALYZE (runs the query, shows actual times)

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 5;
```

Expected output (yours will differ):

```
                                                QUERY PLAN
--------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..12.50 rows=1 width=72) (actual time=0.018..0.142 rows=3 loops=1)
   Filter: (customer_id = 5)
   Rows Removed by Filter: 47
 Planning Time: 0.085 ms
 Execution Time: 0.163 ms
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
EXPLAIN SELECT o.id, c.email
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.total_amount > 100;
```

Expected output (yours will differ):

```
                              QUERY PLAN
-----------------------------------------------------------------------
 Hash Join  (cost=7.50..28.32 rows=25 width=52)
   Hash Cond: (o.customer_id = c.id)
   ->  Seq Scan on orders o  (cost=0.00..15.00 rows=25 width=20)
         Filter: (total_amount > 100)
   ->  Hash  (cost=5.00..5.00 rows=200 width=36)
         ->  Seq Scan on customers c  (cost=0.00..5.00 rows=200 width=36)
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
---------------------------------------------------------
 Seq Scan on products  (cost=0.00..1.50 rows=50 width=120)
(1 row)
```

A Seq Scan is fine for small tables or when fetching most rows. On large tables with selective filters, it signals a missing index.

### Index Scan - uses a B-tree index, follows heap pointers

```sql
EXPLAIN SELECT * FROM customers WHERE id = 42;
```

Expected output (yours will differ):

```
                                  QUERY PLAN
------------------------------------------------------------------------------
 Index Scan using customers_pkey on customers  (cost=0.14..8.16 rows=1 width=80)
   Index Cond: (id = 42)
(2 rows)
```

Index Scan reads the index first to find the row location, then fetches the actual row from the heap. Best for highly selective queries (few rows returned).

### Bitmap Heap Scan - batches index lookups, then fetches heap pages

```sql
EXPLAIN SELECT * FROM orders WHERE total_amount BETWEEN 50 AND 200;
```

Expected output (yours will differ):

```
                                        QUERY PLAN
-------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=4.56..18.23 rows=15 width=72)
   Recheck Cond: ((total_amount >= 50) AND (total_amount <= 200))
   ->  Bitmap Index Scan on orders_total_amount_idx  (cost=0.00..4.55 rows=15 width=0)
         Index Cond: ((total_amount >= 50) AND (total_amount <= 200))
(4 rows)
```

> **Concept - Bitmap Scan**: PostgreSQL first scans the index to build a bitmap of which heap pages contain matching rows. Then it fetches those pages in page order, which is more I/O-efficient than random heap access when many rows match. You often see a `Recheck Cond` because the bitmap can be lossy at high row counts.

### Hash Join - builds a hash table from the smaller relation

```sql
EXPLAIN SELECT p.name, SUM(oi.quantity)
FROM order_items oi
JOIN products p ON oi.product_id = p.id
GROUP BY p.name;
```

Expected output (yours will differ):

```
                              QUERY PLAN
-----------------------------------------------------------------------
 HashAggregate  (cost=35.00..37.00 rows=50 width=44)
   Group Key: p.name
   ->  Hash Join  (cost=3.75..27.50 rows=300 width=28)
         Hash Cond: (oi.product_id = p.id)
         ->  Seq Scan on order_items oi  (cost=0.00..18.00 rows=300 width=12)
         ->  Hash  (cost=2.50..2.50 rows=50 width=20)
               ->  Seq Scan on products p  (cost=0.00..2.50 rows=50 width=20)
(7 rows)
```

Hash Join hashes the smaller table (products, 50 rows) into memory, then probes the hash for each row from the larger table. Efficient when the smaller table fits in `work_mem`.

### Nested Loop - for each outer row, scan the inner relation

```sql
EXPLAIN SELECT c.email, o.total_amount
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE c.id = 10;
```

Expected output (yours will differ):

```
                                      QUERY PLAN
----------------------------------------------------------------------------------
 Nested Loop  (cost=0.28..16.90 rows=2 width=44)
   ->  Index Scan using customers_pkey on customers c  (cost=0.14..8.16 rows=1 width=36)
         Index Cond: (id = 10)
   ->  Index Scan using orders_customer_id_idx on orders o  (cost=0.14..8.22 rows=2 width=12)
         Index Cond: (customer_id = 10)
(5 rows)
```

Nested Loop is efficient when the outer relation is tiny (like one customer). It executes the inner scan once per outer row.

### Merge Join - sorts both sides and merges them

```sql
EXPLAIN SELECT c.email, o.id
FROM customers c
JOIN orders o ON c.id = o.customer_id
ORDER BY c.id;
```

Expected output (yours will differ):

```
                                QUERY PLAN
---------------------------------------------------------------------------
 Merge Join  (cost=30.15..42.65 rows=100 width=44)
   Merge Cond: (c.id = o.customer_id)
   ->  Index Scan using customers_pkey on customers c  ...
   ->  Sort  (cost=14.20..14.45 rows=100 width=12)
         Sort Key: o.customer_id
         ->  Seq Scan on orders o  ...
(6 rows)
```

Merge Join requires both inputs sorted on the join key. It can avoid a sort if an index already provides the order.

---

## 5. EXPLAIN ANALYZE with BUFFERS

BUFFERS shows cache hit and miss counts - critical for diagnosing I/O performance.

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE customer_id = 5;
```

Expected output (yours will differ):

```
                                                    QUERY PLAN
------------------------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..12.50 rows=1 width=72) (actual time=0.015..0.088 rows=3 loops=1)
   Filter: (customer_id = 5)
   Rows Removed by Filter: 47
   Buffers: shared hit=5
 Planning Time: 0.102 ms
 Execution Time: 0.101 ms
(7 rows)
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
       "Total Cost": 12.50,              +
       "Plan Rows": 1,                    +
       "Plan Width": 72,                  +
       "Actual Startup Time": 0.015,      +
       ...
```

The JSON format is machine-readable. Tools like `explain.depesz.com` and `pganalyze` accept this format to render visual plans.

---

## 7. Practical: Compare Two Plans

Run an unoptimized query and compare it to an optimized version.

First, look at the plan for a query with no index on customer_id.

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 99;
```

Note the `Seq Scan` and execution time.

Now create an index.

```
\q
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "CREATE INDEX IF NOT EXISTS orders_customer_id_idx ON orders(customer_id);"
```

Expected output:

```
CREATE INDEX
```

Reconnect and check the plan again.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 99;
```

Expected output (yours will differ):

```
                                                         QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------
 Index Scan using orders_customer_id_idx on orders  (cost=0.14..8.22 rows=2 width=72) (actual time=0.024..0.031 rows=2 loops=1)
   Index Cond: (customer_id = 99)
 Planning Time: 0.112 ms
 Execution Time: 0.048 ms
(4 rows)
```

The plan changed from Seq Scan to Index Scan. Execution time dropped significantly.

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
