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
    indexname     |                      indexdef
------------------+------------------------------------------------------
 orders_pkey      | CREATE UNIQUE INDEX orders_pkey ON orders USING btree (order_id)
(1 row)
```

Run a query that should benefit from an index and check the plan.

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'pending';
```

Expected output (yours will differ):

```
                                  QUERY PLAN
-------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..12.50 rows=15 width=72) (actual time=0.021..0.144 rows=15 loops=1)
   Filter: ((status)::text = 'pending')
   Rows Removed by Filter: 35
 Planning Time: 0.088 ms
 Execution Time: 0.162 ms
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
-------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=4.30..14.55 rows=15 width=72) (actual time=0.038..0.062 rows=15 loops=1)
   Recheck Cond: ((status)::text = 'pending')
   ->  Bitmap Index Scan on idx_orders_status  (cost=0.00..4.26 rows=15 width=0)
         Index Cond: ((status)::text = 'pending')
 Planning Time: 0.244 ms
 Execution Time: 0.082 ms
(6 rows)
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
----------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=4.05..12.30 rows=2 width=72) (actual time=0.028..0.041 rows=2 loops=1)
   Recheck Cond: (customer_id = 42)
   ->  Bitmap Index Scan on idx_orders_customer_hash  (cost=0.00..4.05 rows=2 width=0)
         Index Cond: (customer_id = 42)
 Planning Time: 0.188 ms
 Execution Time: 0.058 ms
(5 rows)
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
    Column     |       Type        | Nullable |      Default
---------------+-------------------+----------+-------------------
 product_id    | integer           | not null | nextval(...)
 name          | character varying | not null |
 price         | numeric(10,2)     | not null |
 stock         | integer           |          |
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
    column_name    |     data_type
-------------------+-------------------
 order_id          | integer
 customer_id       | integer
 product_id        | integer
 quantity          | integer
 total_amount      | numeric
 order_date        | timestamp without time zone
 status            | character varying
 tenant_id         | integer
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
---------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on orders  (cost=4.02..14.55 rows=10 width=72) (actual time=0.033..0.058 rows=8 loops=1)
   Recheck Cond: (order_date >= (now() - '7 days'::interval))
   ->  Bitmap Index Scan on idx_orders_created_brin  (cost=0.00..4.02 rows=10 width=0)
(4 rows)
```

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
--------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_orders_pending on orders  (cost=0.14..10.55 rows=15 width=72) (actual time=0.028..0.047 rows=15 loops=1)
 Planning Time: 0.188 ms
 Execution Time: 0.062 ms
(3 rows)
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
        indexname         | index_size
--------------------------+------------
 orders_pkey              | 16 kB
 idx_orders_status        | 16 kB
 idx_orders_created_brin  | 8 kB
 idx_orders_pending       | 8 kB
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
------------------------------------------------------------------------
 Seq Scan on customers  (cost=0.00..6.00 rows=1 width=80) (actual time=0.018..0.095 rows=1 loops=1)
   Filter: (lower((email)::text) = 'alice@example.com')
   Rows Removed by Filter: 199
 Planning Time: 0.077 ms
 Execution Time: 0.104 ms
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
------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_customers_email_lower on customers  (cost=0.14..8.16 rows=1 width=80) (actual time=0.033..0.036 rows=1 loops=1)
   Index Cond: (lower((email)::text) = 'alice@example.com')
 Planning Time: 0.186 ms
 Execution Time: 0.049 ms
(4 rows)
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
-------------------------------------------------------------------------------------------------------------------------------------------------
 Index Only Scan using idx_orders_customer_covering on orders  (cost=0.14..8.18 rows=2 width=24) (actual time=0.024..0.029 rows=2 loops=1)
   Index Cond: (customer_id = 10)
   Heap Fetches: 0
 Planning Time: 0.142 ms
 Execution Time: 0.042 ms
(5 rows)
```

`Index Only Scan` and `Heap Fetches: 0` confirm that no heap pages were read. All data came from the index itself.

> **Concept - Index-Only Scan and Visibility Map**: Index-Only Scans still need to check the visibility map to confirm rows are visible to the current transaction. If the visibility map is not up to date (table not vacuumed recently), PostgreSQL falls back to heap fetches even with a covering index. Run `VACUUM orders;` if you see `Heap Fetches` unexpectedly high.

---

## 10. Drop Indexes You No Longer Need

Indexes cost write performance (every INSERT/UPDATE/DELETE must update all indexes). Review unused indexes regularly.

```sql
SELECT indexname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE tablename = 'orders'
ORDER BY idx_scan;
```

Expected output (yours will differ):

```
          indexname           | idx_scan | idx_tup_read
------------------------------+----------+--------------
 idx_orders_created_brin      |        0 |            0
 idx_orders_status            |        2 |           30
 idx_orders_customer_covering |        3 |            6
 orders_pkey                  |       12 |           12
(4 rows)
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
