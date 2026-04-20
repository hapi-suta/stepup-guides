# Exercise 02: Data Cleanup

**Duration:** 30 minutes
**Objective:** Find and fix three classes of data quality problems: duplicate records, NULL values in required fields, and orphaned foreign key references. Use SELECT to diagnose before UPDATE or DELETE to fix.

**Prerequisites:** Build guide 03 (data modification) complete.

---

## Background

Bad data quietly accumulates in production databases. Your job is to find it and fix it safely. The golden rule: always SELECT first to see exactly what you will change, then run the modification.

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

All exercises below work on the `cleanup_*` tables.

---

## Problem 1: Duplicate Customer Records

A batch import ran twice and created duplicate customer records with the same email address.

First, inject some duplicates so you have something to find:

```sql
INSERT INTO cleanup_customers (name, email, created_at)
SELECT name, email, now()
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

**Step 2 - See the duplicate rows:**

```sql
SELECT customer_id, name, email, created_at
FROM cleanup_customers
WHERE email IN (
  SELECT email FROM cleanup_customers GROUP BY email HAVING COUNT(*) > 1
)
ORDER BY email, customer_id;
```

**Step 3 - Delete duplicates, keep lowest customer_id:**

```sql
DELETE FROM cleanup_customers
WHERE customer_id NOT IN (
  SELECT MIN(customer_id) FROM cleanup_customers GROUP BY email
);
```

Verify no duplicates remain:

```sql
SELECT email, COUNT(*) FROM cleanup_customers GROUP BY email HAVING COUNT(*) > 1;
```

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

**Step 2 - Check which have items:**

```sql
SELECT o.order_id, COUNT(oi.item_id) AS item_count
FROM cleanup_orders o
LEFT JOIN cleanup_order_items oi ON o.order_id = oi.order_id
WHERE o.customer_id IS NULL
GROUP BY o.order_id
ORDER BY item_count DESC;
```

**Step 3 - Delete empty orphaned orders:**

```sql
DELETE FROM cleanup_orders
WHERE customer_id IS NULL
  AND order_id NOT IN (SELECT DISTINCT order_id FROM cleanup_order_items);
```

**Step 4 - Create placeholder and assign:**

```sql
INSERT INTO cleanup_customers (name, email)
VALUES ('Unknown Customer', 'unknown@placeholder.invalid')
RETURNING customer_id;
```

```sql
UPDATE cleanup_orders
SET customer_id = (
  SELECT customer_id FROM cleanup_customers WHERE email = 'unknown@placeholder.invalid'
)
WHERE customer_id IS NULL;
```

Verify:

```sql
SELECT COUNT(*) FROM cleanup_orders WHERE customer_id IS NULL;
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
SELECT oi.*
FROM cleanup_order_items oi
LEFT JOIN cleanup_orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;
```

**Step 2 - Calculate orphaned revenue:**

```sql
SELECT SUM(quantity * unit_price) AS orphaned_revenue
FROM cleanup_order_items oi
WHERE NOT EXISTS (
  SELECT 1 FROM cleanup_orders o WHERE o.order_id = oi.order_id
);
```

**Step 3 - Delete orphans:**

```sql
DELETE FROM cleanup_order_items
WHERE order_id NOT IN (SELECT order_id FROM cleanup_orders);
```

Verify:

```sql
SELECT COUNT(*)
FROM cleanup_order_items oi
LEFT JOIN cleanup_orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;
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
