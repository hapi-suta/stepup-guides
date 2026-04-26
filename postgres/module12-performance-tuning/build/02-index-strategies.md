# Guide 02 - Index Strategies

Learn the five PostgreSQL index types, when to use each one, and how to build partial, expression, and covering indexes that eliminate unnecessary heap fetches.

**Server:** NODE1 only

---

## What You Will Learn

- B-tree, Hash, GIN, GiST, and BRIN index types and their use cases
- Partial indexes to index only the rows you care about
- Expression indexes to index transformed values
- Covering indexes (INCLUDE) to avoid heap access entirely
- How to measure the impact of each index with EXPLAIN ANALYZE

---

## 1. Connect to the Server

SSH into NODE1.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

Switch to postgres.

```
sudo -iu postgres
```

Connect to stepup_store.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Expected output (yours will differ):

```
psql (16.x)
stepup_store=#
```

---

## 2. B-tree Index - the Default

B-tree is PostgreSQL's default index type. Use it for equality and range queries on orderable data: integers, text, dates, numeric.

Check what indexes already exist on orders.

```sql
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders';
```

Expected output (yours will differ):

```
  indexname  |                                indexdef
-------------+-------------------------------------------------------------------------
 orders_pkey | CREATE UNIQUE INDEX orders_pkey ON public.orders USING btree (order_id)
(1 row)
```

Run a query that should benefit from an index and check the plan.

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'pending';
```

Expected output (yours will differ):

```
                                                 QUERY PLAN
------------------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..1093.00 rows=12480 width=43) (actual time=0.007..5.881 rows=12573 loops=1)
   Filter: ((status)::text = 'pending'::text)
   Rows Removed by Filter: 37427
 Planning Time: 0.248 ms
 Execution Time: 6.277 ms
(5 rows)
```

Create a B-tree index on status.

```sql
CREATE INDEX idx_orders_status ON orders(status);
```

Expected output:

```
CREATE INDEX
```

Run the same query again.

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'pending';
```

Expected output (yours will differ):

```
                                                             QUERY PLAN
------------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=145.01..769.01 rows=12480 width=43) (actual time=0.508..2.702 rows=12573 loops=1)
   Recheck Cond: ((status)::text = 'pending'::text)
   Heap Blocks: exact=468
   ->  Bitmap Index Scan on idx_orders_status  (cost=0.00..141.89 rows=12480 width=0) (actual time=0.452..0.452 rows=12573 loops=1)
         Index Cond: ((status)::text = 'pending'::text)
 Planning Time: 0.212 ms
 Execution Time: 3.097 ms
(7 rows)
```

> **Concept - When B-tree Helps**: B-tree indexes support `=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `IN`, `LIKE 'prefix%'`, and `IS NULL`. They do NOT help with `LIKE '%suffix'` or case-insensitive searches. For those patterns you need GIN or an expression index.

---

## 3. Hash Index - equality only, smaller than B-tree

Hash indexes are optimized for equality (`=`) comparisons only. They cannot be used for range queries.

Create a hash index on customer_id.

```sql
CREATE INDEX idx_orders_customer_hash ON orders USING hash(customer_id);
```

Expected output:

```
CREATE INDEX
```

Test it with an equality query.

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 42;
```

Expected output (yours will differ):

```
                                                           QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=4.04..22.55 rows=5 width=43) (actual time=0.018..0.020 rows=2 loops=1)
   Recheck Cond: (customer_id = 42)
   Heap Blocks: exact=2
   ->  Bitmap Index Scan on idx_orders_customer_hash  (cost=0.00..4.04 rows=5 width=0) (actual time=0.013..0.013 rows=2 loops=1)
         Index Cond: (customer_id = 42)
 Planning Time: 0.160 ms
 Execution Time: 0.038 ms
(7 rows)
```

In practice, B-tree handles equality just as well as hash. Use hash only when you have verified profiling that shows a benefit for your specific workload.

Drop the hash index since we don't need it competing with B-tree.

```sql
DROP INDEX idx_orders_customer_hash;
```

Expected output:

```
DROP INDEX
```

---

## 4. GIN Index - for arrays, JSONB, full-text search

GIN (Generalized Inverted Index) indexes the internal elements of composite values. Use it for arrays, JSONB columns, and full-text search vectors.

Check if there is a JSONB or text column to work with.

```sql
\d products
```

Expected output (yours will differ):

```
                                          Table "public.products"
   Column   |          Type          | Collation | Nullable |                   Default
------------+------------------------+-----------+----------+----------------------------------------------
 product_id | integer                |           | not null | nextval('products_product_id_seq'::regclass)
 name       | character varying(150) |           | not null |
 price      | numeric(10,2)          |           | not null |
 stock      | integer                |           |          | 0
```

Create a GIN index for full-text search on product names.

```sql
CREATE INDEX idx_products_name_fts
ON products
USING GIN(to_tsvector('english', name));
```

Expected output:

```
CREATE INDEX
```

Test the full-text search.

```sql
EXPLAIN ANALYZE
SELECT product_id, name, price
FROM products
WHERE to_tsvector('english', name) @@ plainto_tsquery('english', 'wireless');
```

Expected output (yours will differ):

```
                                                              QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on products  (cost=8.25..15.40 rows=1 width=48) (actual time=0.245..0.249 rows=3 loops=1)
   Recheck Cond: (to_tsvector('english'::regconfig, (name)::text) @@ ...)
   ->  Bitmap Index Scan on idx_products_name_fts  (cost=0.00..8.25 rows=1 width=0)
(4 rows)
```

> **Concept - GIN vs GiST for Full-Text**: GIN builds an index entry for every lexeme (word) in the document. Lookups are faster. GiST builds lossy index entries and must recheck results. GIN indexes are larger and slower to build, but faster at query time. For full-text search, prefer GIN unless you need nearest-neighbor (similarity) searches.

---

## 5. GiST Index - for geometric types, ranges, and similarity

GiST (Generalized Search Tree) supports complex data types like geometric shapes, network addresses, and ranges.

Check if any range columns exist or create a range example.

```sql
CREATE INDEX idx_products_price_range
ON products
USING GiST(numrange(price, price, '[]'));
```

Expected output:

```
CREATE INDEX
```

A more common real-world use: INET addresses for network containment queries.

```sql
\d customers
```

Look for an inet or IP address column. If there is none, the key point is the syntax. Drop the temporary index.

```sql
DROP INDEX idx_products_price_range;
```

Expected output:

```
DROP INDEX
```

---

## 6. BRIN Index - for naturally ordered columns (time series, sequences)

BRIN (Block Range Index) stores the min/max values for ranges of physical disk pages. It is tiny compared to B-tree but only works when data is physically ordered by the column (like timestamps written in order).

Check the orders table for an order_date or ordered_at column.

```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'orders' AND table_schema = 'public';
```

Expected output (yours will differ):

```
 column_name  |          data_type
--------------+-----------------------------
 order_id     | integer
 customer_id  | integer
 product_id   | integer
 quantity     | integer
 total_amount | numeric
 order_date   | timestamp without time zone
 status       | character varying
 tenant_id    | integer
(8 rows)
```

Create a BRIN index on order_date.

```sql
CREATE INDEX idx_orders_created_brin ON orders USING BRIN(order_date);
```

Expected output:

```
CREATE INDEX
```

Test a date range query.

```sql
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE order_date >= NOW() - INTERVAL '7 days';
```

Expected output (yours will differ):

```
                                                QUERY PLAN
----------------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..1343.00 rows=1115 width=43) (actual time=0.019..11.258 rows=903 loops=1)
   Filter: (order_date >= (now() - '7 days'::interval))
   Rows Removed by Filter: 49097
 Planning Time: 0.146 ms
 Execution Time: 11.306 ms
(5 rows)
```

Notice the planner chose Seq Scan even with the BRIN index. This is because the order_date values in our lab data are randomly distributed, not physically ordered on disk. BRIN only helps when data is inserted in chronological order (append-only patterns like logs or events). This is exactly why BRIN is NOT a general-purpose replacement for B-tree.

> **Concept - BRIN Size Advantage**: A BRIN index on a 100 million row time-series table can be just a few MB, while a B-tree would be gigabytes. The trade-off is accuracy - BRIN must recheck results and works poorly on unsorted data. For write-heavy append-only tables (logs, events, audit trails), BRIN is the right default.

---

## 7. Partial Indexes - index only the rows you care about

A partial index only indexes rows that match a WHERE clause. This makes the index smaller and faster.

The orders table has a status column. Most queries care about 'pending' orders, not completed ones.

```sql
CREATE INDEX idx_orders_pending
ON orders(order_date)
WHERE status = 'pending';
```

Expected output:

```
CREATE INDEX
```

This index is only used when the query also filters on `status = 'pending'`.

```sql
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE status = 'pending'
ORDER BY order_date;
```

Expected output (yours will differ):

```
                                                                QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=1594.90..1626.10 rows=12480 width=43) (actual time=5.008..6.615 rows=12573 loops=1)
   Sort Key: order_date
   Sort Method: quicksort  Memory: 1269kB
   ->  Bitmap Heap Scan on orders  (cost=121.81..745.81 rows=12480 width=43) (actual time=0.462..2.630 rows=12573 loops=1)
         Recheck Cond: ((status)::text = 'pending'::text)
         Heap Blocks: exact=468
         ->  Bitmap Index Scan on idx_orders_pending  (cost=0.00..118.69 rows=12480 width=0) (actual time=0.407..0.408 rows=12573 loops=1)
 Planning Time: 0.205 ms
 Execution Time: 7.034 ms
(9 rows)
```

Compare the index sizes.

```sql
SELECT indexname,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_indexes
WHERE tablename = 'orders';
```

Expected output (yours will differ):

```
        indexname        | index_size
-------------------------+------------
 orders_pkey             | 1112 kB
 idx_orders_status       | 360 kB
 idx_orders_created_brin | 24 kB
 idx_orders_pending      | 112 kB
(4 rows)
```

The partial index is smaller because it only covers the pending rows.

---

## 8. Expression Indexes - index a computed value

An expression index stores the result of a function. Use it when your queries always apply the same transform to a column.

A common case is case-insensitive searches.

```sql
EXPLAIN ANALYZE
SELECT * FROM customers WHERE lower(email) = 'alice@example.com';
```

Expected output (yours will differ):

```
                                              QUERY PLAN
-------------------------------------------------------------------------------------------------------
 Seq Scan on customers  (cost=0.00..264.00 rows=50 width=57) (actual time=4.412..4.413 rows=1 loops=1)
   Filter: (lower((email)::text) = 'alice@example.com'::text)
   Rows Removed by Filter: 9999
 Planning Time: 0.098 ms
 Execution Time: 4.424 ms
(5 rows)
```

Create an expression index on lower(email).

```sql
CREATE INDEX idx_customers_email_lower ON customers(lower(email));
```

Expected output:

```
CREATE INDEX
```

Run the query again.

```sql
EXPLAIN ANALYZE
SELECT * FROM customers WHERE lower(email) = 'alice@example.com';
```

Expected output (yours will differ):

```
                                                            QUERY PLAN
-----------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on customers  (cost=4.67..96.94 rows=50 width=57) (actual time=0.019..0.020 rows=1 loops=1)
   Recheck Cond: (lower((email)::text) = 'alice@example.com'::text)
   Heap Blocks: exact=1
   ->  Bitmap Index Scan on idx_customers_email_lower  (cost=0.00..4.66 rows=50 width=0) (actual time=0.016..0.016 rows=1 loops=1)
         Index Cond: (lower((email)::text) = 'alice@example.com'::text)
 Planning Time: 0.168 ms
 Execution Time: 0.039 ms
(7 rows)
```

The index is used because the query expression `lower(email)` exactly matches the index expression.

> **Concept - Expression Index Match**: For an expression index to be used, the query's WHERE clause must use the **exact same expression** as the index definition. `lower(email) = 'x'` uses `idx_customers_email_lower`. But `email ILIKE 'x'` does NOT - it is a different expression. When in doubt, check with EXPLAIN.

---

## 9. Covering Indexes (INCLUDE) - avoid the heap entirely

A covering index stores extra columns in the index leaf pages so that the query can be satisfied entirely from the index, without touching the heap at all. This is called an "index-only scan."

```sql
CREATE INDEX idx_orders_customer_covering
ON orders(customer_id)
INCLUDE (total_amount, status);
```

Expected output:

```
CREATE INDEX
```

Run a query that only needs customer_id, total_amount, and status.

```sql
EXPLAIN ANALYZE
SELECT customer_id, total_amount, status
FROM orders
WHERE customer_id = 10;
```

Expected output (yours will differ):

```
                                                                QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------
 Index Only Scan using idx_orders_customer_covering on orders  (cost=0.41..4.50 rows=5 width=19) (actual time=0.023..0.023 rows=4 loops=1)
   Index Cond: (customer_id = 10)
   Heap Fetches: 0
 Planning Time: 0.142 ms
 Execution Time: 0.037 ms
(5 rows)
```

`Index Only Scan` and `Heap Fetches: 0` confirm that no heap pages were read. All data came from the index itself.

> **Concept - Index-Only Scan and Visibility Map**: Index-Only Scans still need to check the visibility map to confirm rows are visible to the current transaction. If the visibility map is not up to date (table not vacuumed recently), PostgreSQL falls back to heap fetches even with a covering index. Run `VACUUM orders;` if you see `Heap Fetches` unexpectedly high.

---

## 10. Drop Indexes You No Longer Need

Indexes cost write performance (every INSERT/UPDATE/DELETE must update all indexes). Review unused indexes regularly.

```sql
SELECT indexrelname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE relname = 'orders'
ORDER BY idx_scan;
```

Expected output (yours will differ):

```
       indexrelname        | idx_scan | idx_tup_read
---------------------------+----------+--------------
 idx_orders_created_brin   |        0 |            0
 idx_orders_status         |        2 |        25146
 idx_orders_pending        |        1 |        12573
 idx_orders_customer_covering |     1 |            4
 orders_pkey               |        0 |            0
(5 rows)
```

Indexes with `idx_scan = 0` after weeks of production traffic are candidates for removal.

```
\q
```

```
exit
```

---

## Checkpoint

By the end of this guide you should be able to:

- [ ] Choose the correct index type for a given access pattern
- [ ] Create a partial index that only indexes rows matching a condition
- [ ] Create an expression index on a function like lower()
- [ ] Create a covering index with INCLUDE and verify Index-Only Scan in EXPLAIN
- [ ] Check pg_stat_user_indexes to identify unused indexes

---

**Proceed to:** [Guide 03 - Memory Tuning](./03-memory-tuning.md)
