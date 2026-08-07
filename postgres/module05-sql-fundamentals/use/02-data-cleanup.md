# Exercise 02: Data Cleanup

**Duration:** 30 minutes
**Objective:** Find and fix three classes of data quality problems: duplicate records, NULL values in required fields, and orphaned foreign key references. Use SELECT to diagnose before UPDATE or DELETE to fix.

**Prerequisites:** Build guide 03 (data modification) complete.

---

## Background

Bad data quietly accumulates in production databases. Your job is to find it and fix it safely. The golden rule: always SELECT first to see exactly what you will change, then run the modification.

Reminder: `customers` has separate `first_name` and `last_name` columns, and a `joined_at` timestamp - there is no single `name` column and no `created_at` column on that table.

Connect before starting:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Create a working copy of the data so you do not damage the live tables:

Create a working copy of the customers table:

```sql
CREATE TABLE IF NOT EXISTS cleanup_customers AS SELECT * FROM customers;
```

Create a working copy of the orders table:

```sql
CREATE TABLE IF NOT EXISTS cleanup_orders AS SELECT * FROM orders;
```

Create a working copy of the order_items table:

```sql
CREATE TABLE IF NOT EXISTS cleanup_order_items AS SELECT * FROM order_items;
```

`CREATE TABLE ... AS SELECT` (CTAS) copies the data and column types, but it does **not** carry over the primary key or the auto-incrementing sequence behind `customer_id`. Add both back to `cleanup_customers` so that inserting a new row without specifying `customer_id` still works the way it does on the real `customers` table:

```sql
ALTER TABLE cleanup_customers ADD PRIMARY KEY (customer_id);
CREATE SEQUENCE cleanup_customers_customer_id_seq OWNED BY cleanup_customers.customer_id;
SELECT setval('cleanup_customers_customer_id_seq', (SELECT MAX(customer_id) FROM cleanup_customers));
ALTER TABLE cleanup_customers ALTER COLUMN customer_id SET DEFAULT nextval('cleanup_customers_customer_id_seq');
```

All exercises below work on the `cleanup_*` tables.

---

## Problem 1: Duplicate Customer Records

A batch import ran twice and created duplicate customer records with the same email address.

First, inject some duplicates so you have something to find. Because `customer_id` now has a working default (from the setup step above), this INSERT does not need to specify it - PostgreSQL assigns the next sequence value automatically, just like a fresh signup:

```sql
INSERT INTO cleanup_customers (first_name, last_name, email, city, state, joined_at)
SELECT first_name, last_name, email, city, state, now()
FROM cleanup_customers
WHERE customer_id IN (1, 2, 3);
```

### Your Task

1. Write a query to find all email addresses that appear more than once in `cleanup_customers`.
2. For each duplicate email, identify which `customer_id` is the original (lowest ID) and which are copies (higher IDs).
3. Delete the duplicate rows (the higher IDs), keeping only the original.

**Hint for step 1:** Use `GROUP BY email HAVING COUNT(*) > 1`.

**Hint for step 3:** Use a subquery to find the minimum customer_id per email, then delete rows where the ID is not the minimum.

### Answer

**Step 1 - Find duplicates:**

```sql
SELECT email, COUNT(*) AS occurrences
FROM cleanup_customers
GROUP BY email
HAVING COUNT(*) > 1
ORDER BY email;
```

Expected output:

```
       email       | occurrences
-------------------+-------------
 alice@example.com |           2
 bob@example.com   |           2
 carol@example.com |           2
(3 rows)
```

**Step 2 - See the duplicate rows:**

```sql
SELECT customer_id, first_name, last_name, email, joined_at
FROM cleanup_customers
WHERE email IN (
  SELECT email FROM cleanup_customers GROUP BY email HAVING COUNT(*) > 1
)
ORDER BY email, customer_id;
```

Expected output (yours will differ in the exact new customer_id values and the `joined_at` timestamp on the copies):

```
 customer_id | first_name | last_name |       email       |         joined_at
-------------+------------+-----------+--------------------+----------------------------
           1 | Alice      | Chen      | alice@example.com | 2026-08-07 01:54:36.120311
          11 | Alice      | Chen      | alice@example.com | 2026-08-07 02:12:38.995272
           2 | Bob        | Smith     | bob@example.com   | 2026-08-07 01:54:36.120311
          12 | Bob        | Smith     | bob@example.com   | 2026-08-07 02:12:38.995272
           3 | Carol      | Davis     | carol@example.com | 2026-08-07 01:54:36.120311
          13 | Carol      | Davis     | carol@example.com | 2026-08-07 02:12:38.995272
(6 rows)
```

**Step 3 - Delete duplicates, keep lowest customer_id:**

```sql
DELETE FROM cleanup_customers
WHERE customer_id NOT IN (
  SELECT MIN(customer_id) FROM cleanup_customers GROUP BY email
);
```

Expected output:

```
DELETE 3
```

Verify no duplicates remain:

```sql
SELECT email, COUNT(*) FROM cleanup_customers GROUP BY email HAVING COUNT(*) > 1;
```

Expected output:

```
 email | count
-------+-------
(0 rows)
```

> **Concept: NOT IN and NULL**
> `NOT IN` compares against every value the subquery returns. If any customer in the table had a NULL `customer_id`, `customer_id NOT IN (...)` would evaluate to NULL (not TRUE) for that row, and DELETE would silently skip it - a classic and dangerous gotcha. This is one reason the setup step above gives `cleanup_customers.customer_id` a real, non-null default: every row here has a genuine integer ID, so `NOT IN` behaves as expected.

---

## Problem 2: NULL Values in Required Fields

Some orders were inserted without a `customer_id`. These orders cannot be linked to any customer and should either be fixed or removed.

Inject some NULLs:

```sql
UPDATE cleanup_orders SET customer_id = NULL WHERE order_id IN (5, 10, 15, 20);
```

### Your Task

1. Count how many orders have a NULL `customer_id`.
2. Check if any of these orders have order_items (they may have revenue that matters).
3. For orders with NULL customer_id that have no order_items, delete them.
4. For orders with NULL customer_id that DO have order_items, assign them to a placeholder "Unknown Customer" - you will need to insert that customer first.

### Answer

**Step 1 - Count orphans:**

```sql
SELECT COUNT(*) AS orders_without_customer
FROM cleanup_orders
WHERE customer_id IS NULL;
```

Expected output:

```
 orders_without_customer
-------------------------
                       4
(1 row)
```

**Step 2 - Check which have items:**

```sql
SELECT o.order_id, COUNT(oi.item_id) AS item_count
FROM cleanup_orders o
LEFT JOIN cleanup_order_items oi ON o.order_id = oi.order_id
WHERE o.customer_id IS NULL
GROUP BY o.order_id
ORDER BY item_count DESC;
```

Expected output (yours will differ - depends on which orders happened to get order_items when your lab was seeded):

```
 order_id | item_count
----------+------------
       15 |          1
       10 |          1
        5 |          1
       20 |          1
(4 rows)
```

**Step 3 - Delete empty orphaned orders:**

```sql
DELETE FROM cleanup_orders
WHERE customer_id IS NULL
  AND order_id NOT IN (SELECT DISTINCT order_id FROM cleanup_order_items WHERE order_id IS NOT NULL);
```

Expected output (yours will differ - `0` if, like in Step 2 above, every NULL-customer order turned out to have at least one item):

```
DELETE 0
```

**Step 4 - Create placeholder and assign:**

```sql
INSERT INTO cleanup_customers (first_name, last_name, email)
VALUES ('Unknown', 'Customer', 'unknown@placeholder.invalid')
RETURNING customer_id;
```

Expected output (yours will differ - the ID depends on how many rows you inserted in Problem 1):

```
 customer_id
-------------
          14
(1 row)
```

```sql
UPDATE cleanup_orders
SET customer_id = (
  SELECT customer_id FROM cleanup_customers WHERE email = 'unknown@placeholder.invalid'
)
WHERE customer_id IS NULL;
```

Expected output:

```
UPDATE 4
```

Verify:

```sql
SELECT COUNT(*) FROM cleanup_orders WHERE customer_id IS NULL;
```

Expected output:

```
 count
-------
     0
(1 row)
```

---

## Problem 3: Orphaned order_items

Some `order_items` rows reference `order_id` values that no longer exist in `cleanup_orders`. This happens when orders are deleted without cascading the delete to order_items.

Inject orphans:

```sql
INSERT INTO cleanup_order_items (order_id, product_id, quantity, unit_price)
VALUES (99999, 1, 2, 9.99), (99998, 2, 1, 29.99);
```

### Your Task

1. Find all `cleanup_order_items` rows where the `order_id` does not exist in `cleanup_orders`.
2. Report the total revenue represented by these orphaned items.
3. Delete the orphaned items.

### Answer

**Step 1 - Find orphans:**

```sql
SELECT oi.order_id, oi.product_id, oi.quantity, oi.unit_price
FROM cleanup_order_items oi
LEFT JOIN cleanup_orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;
```

Expected output:

```
 order_id | product_id | quantity | unit_price
----------+------------+----------+------------
    99999 |          1 |        2 |       9.99
    99998 |          2 |        1 |      29.99
(2 rows)
```

**Step 2 - Calculate orphaned revenue:**

```sql
SELECT SUM(quantity * unit_price) AS orphaned_revenue
FROM cleanup_order_items oi
WHERE NOT EXISTS (
  SELECT 1 FROM cleanup_orders o WHERE o.order_id = oi.order_id
);
```

Expected output:

```
 orphaned_revenue
------------------
            49.97
(1 row)
```

**Step 3 - Delete orphans:**

```sql
DELETE FROM cleanup_order_items
WHERE order_id NOT IN (SELECT order_id FROM cleanup_orders);
```

Expected output:

```
DELETE 2
```

Verify:

```sql
SELECT COUNT(*)
FROM cleanup_order_items oi
LEFT JOIN cleanup_orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;
```

Expected output:

```
 count
-------
     0
(1 row)
```

---

## Cleanup

Drop the working tables:

```sql
DROP TABLE IF EXISTS cleanup_customers;
```

```sql
DROP TABLE IF EXISTS cleanup_orders;
```

```sql
DROP TABLE IF EXISTS cleanup_order_items;
```

Exit:

```sql
\q
```

```bash
exit
```
