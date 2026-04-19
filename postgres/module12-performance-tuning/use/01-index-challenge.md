# Use Exercise 01 - Index Challenge

Given five slow queries, add the right indexes to make them fast. Prove the improvement with EXPLAIN ANALYZE before and after.

**Server:** NODE1 only

---

## Setup

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

---

## Challenge 1 - Orders by Status and Date

This query is used by the operations dashboard. It is slow.

```sql
EXPLAIN ANALYZE
SELECT id, total_amount, created_at
FROM orders
WHERE status = 'shipped'
  AND created_at >= NOW() - INTERVAL '14 days'
ORDER BY created_at DESC;
```

Note the plan. Is it using any indexes? What is the execution time?

Your task: create the most efficient index for this query.

**Hint:** Composite indexes serve multiple columns. Column order matters - put the most selective or most-filtered column first.

When you have your index, run EXPLAIN ANALYZE again and verify the plan changed.

---

## Challenge 2 - Customer Email Lookup (Case-Insensitive)

The application searches for customers by email regardless of how the user typed it.

```sql
EXPLAIN ANALYZE
SELECT id, first_name, last_name, email
FROM customers
WHERE lower(email) = lower('ALICE@EXAMPLE.COM');
```

Note the plan. Is the existing email index being used?

Your task: create the right type of index so this query uses an Index Scan.

**Hint:** When the query applies a function to the column, only one kind of index helps.

Run EXPLAIN ANALYZE after creating the index and verify `Index Scan` appears in the plan.

---

## Challenge 3 - Order Items for Recent Orders Only

This query fetches line items for orders placed in the last 7 days. It joins two tables.

```sql
EXPLAIN ANALYZE
SELECT oi.id, oi.quantity, oi.unit_price, o.created_at
FROM order_items oi
JOIN orders o ON oi.order_id = o.id
WHERE o.created_at >= NOW() - INTERVAL '7 days';
```

Note the plan. How many rows does the Seq Scan on order_items read?

Your task: create indexes on both `orders.created_at` and `order_items.order_id` and compare the plan.

Run EXPLAIN ANALYZE after and confirm both index scans appear.

---

## Challenge 4 - Products by Category and Price Range

The storefront runs this filter frequently.

```sql
EXPLAIN ANALYZE
SELECT id, name, price
FROM products
WHERE category = 'Electronics'
  AND price BETWEEN 50 AND 300;
```

Note the plan. What is the execution time?

Your task: create a covering index that allows an Index-Only Scan (no heap access).

**Hint:** The query only selects id, name, and price. A covering index can include those columns.

Run EXPLAIN ANALYZE after and verify `Index Only Scan` and `Heap Fetches: 0`.

---

## Challenge 5 - High-Value Pending Orders

This fraud check query runs every minute. It only cares about a small subset of rows.

```sql
EXPLAIN ANALYZE
SELECT id, customer_id, total_amount
FROM orders
WHERE status = 'pending'
  AND total_amount > 500;
```

Note how many rows the Seq Scan reads vs how many match.

Your task: create a partial index that only covers the rows this query cares about.

**Hint:** A partial index has a WHERE clause that matches the query's most selective constant filter.

Run EXPLAIN ANALYZE after and confirm the partial index is used and the index is smaller than a full index.

---

## Verify Your Work

After completing all five challenges, run this summary query to see your new indexes.

```sql
SELECT
  indexname,
  indexdef,
  pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
FROM pg_indexes
WHERE tablename IN ('orders', 'customers', 'products', 'order_items')
  AND indexname NOT LIKE '%pkey'
ORDER BY tablename, indexname;
```

Expected output (yours will differ - should show your new indexes):

```
             indexname              | ... | size
------------------------------------+-----+-------
 idx_customers_email_lower          | ... | 8 kB
 idx_order_items_order_id           | ... | 16 kB
 idx_orders_created_at              | ... | 16 kB
 idx_orders_status_created_covering | ... | 24 kB
 idx_orders_high_value_pending      | ... | 8 kB
 idx_products_category_price        | ... | 8 kB
(6 rows)
```

```
\q
```

```
exit
```

---

## Checkpoint

- [ ] All five queries now show Index Scan, Bitmap Index Scan, or Index Only Scan in EXPLAIN
- [ ] Challenge 4 shows `Heap Fetches: 0` (Index Only Scan)
- [ ] Challenge 5 partial index is smaller than a full index on status would be
- [ ] You can explain WHY each index type was correct for each challenge
