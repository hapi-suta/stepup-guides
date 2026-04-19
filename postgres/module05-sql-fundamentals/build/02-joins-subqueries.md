# Module 05 - SQL Fundamentals
## Guide 02: Joins and Subqueries

**Objective:** Combine data from multiple tables using INNER JOIN, LEFT JOIN, RIGHT JOIN, and CROSS JOIN. Write scalar, correlated, and EXISTS subqueries. Use real order, customer, and product data from `stepup_store`.

**Time:** 40-45 minutes

**Prerequisites:**
- Guide 01 complete - you understand SELECT, WHERE, ORDER BY, GROUP BY
- PostgreSQL 16 running, connected to `stepup_store`

---

## 1. Connect

Log in to your server:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open psql against the store database:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Expected output (yours will differ):

```
psql (16.x)
Type "help" for help.

stepup_store=#
```

---

## 2. Understand the Relationships

Before writing joins, understand how the tables relate. View the foreign key structure:

```sql
\d order_items
```

Expected output (yours will differ):

```
                                  Table "public.order_items"
    Column    |   Type        | Nullable |              Default
--------------+---------------+----------+-----------------------------------
 item_id      | integer       | not null | nextval(...)
 order_id     | integer       |          |
 product_id   | integer       |          |
 quantity     | integer       |          |
 unit_price   | numeric(10,2) |          |
Foreign-key constraints:
    "order_items_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(order_id)
    "order_items_product_id_fkey" FOREIGN KEY (product_id) REFERENCES products(product_id)
```

The relationship chain is: `customers` -> `orders` -> `order_items` -> `products`. One customer has many orders. One order has many order_items. Each order_item references one product.

> **Concept: Why store data across multiple tables?**
> Storing customer information once in `customers` and referencing it by `customer_id` in `orders` is called normalization. Without it, every order would store the full customer address - a 100,000-row orders table with 1,000 customers would store each customer's name and address an average of 100 times. Joins let you reconstruct the full picture at query time without duplicating the data at storage time.

---

## 3. INNER JOIN

An INNER JOIN returns only rows where the join condition matches in both tables. Rows with no match on either side are excluded.

Join orders with customers to see who placed each order:

```sql
SELECT o.order_id, c.name AS customer_name, o.total_amount, o.status
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_id
LIMIT 10;
```

Expected output (yours will differ):

```
 order_id |  customer_name  | total_amount |  status
----------+-----------------+--------------+-----------
        1 | Alice Johnson   |       125.97 | completed
        2 | Bob Smith       |        49.99 | pending
        3 | Alice Johnson   |        89.95 | completed
...
(10 rows)
```

Note the table aliases: `o` for orders, `c` for customers. These shorten the query and avoid ambiguity when two tables have columns with the same name.

Join three tables - orders, customers, and order_items - to see what each order contains:

```sql
SELECT o.order_id, c.name AS customer_name, p.name AS product_name, oi.quantity, oi.unit_price
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
INNER JOIN order_items oi ON o.order_id = oi.order_id
INNER JOIN products p ON oi.product_id = p.product_id
ORDER BY o.order_id, p.name
LIMIT 15;
```

Expected output (yours will differ):

```
 order_id | customer_name |  product_name  | quantity | unit_price
----------+---------------+----------------+----------+------------
        1 | Alice Johnson | Gadget Plus    |        1 |      49.99
        1 | Alice Johnson | Widget Pro     |        2 |      29.99
        2 | Bob Smith     | Super Cable    |        3 |       9.99
...
(15 rows)
```

> **Concept: Join condition cardinality**
> When joining `orders` (300 rows) to `order_items` (average 3 items per order = 900 rows), the result has 900 rows - one per order_item. Each order row is repeated for every matching order_item. If you then aggregate with `SUM(oi.unit_price * oi.quantity)`, you get the correct order total. If you try to `SUM(o.total_amount)` after this join, you will count it three times for an order with three items. Always be aware of how joins change the row count.

---

## 4. LEFT JOIN

A LEFT JOIN returns all rows from the left table, plus matching rows from the right table. When there is no match on the right side, NULL fills the right-table columns.

Find customers and their orders - include customers who have never ordered:

```sql
SELECT c.customer_id, c.name, o.order_id, o.total_amount
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
ORDER BY c.customer_id
LIMIT 15;
```

Expected output (yours will differ):

```
 customer_id |     name      | order_id | total_amount
-------------+---------------+----------+--------------
           1 | Alice Johnson |        1 |       125.97
           1 | Alice Johnson |        3 |        89.95
           2 | Bob Smith     |        2 |        49.99
          15 | New Customer  |     NULL |         NULL
...
```

The customer `New Customer` has no orders - their row still appears but order columns are NULL. An INNER JOIN would have silently excluded this customer.

Find customers who have never placed an order. The pattern is LEFT JOIN + WHERE right_table.id IS NULL:

```sql
SELECT c.customer_id, c.name
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;
```

Expected output (yours will differ):

```
 customer_id |     name
-------------+--------------
          15 | New Customer
(1 row)
```

> **Concept: LEFT JOIN vs INNER JOIN choice**
> Use INNER JOIN when you only care about rows that have matches on both sides. Use LEFT JOIN when you want to keep all rows from the left table even if no match exists on the right. The "never ordered" pattern (LEFT JOIN + WHERE right IS NULL) is a common and efficient way to find missing relationships without a subquery.

---

## 5. RIGHT JOIN

A RIGHT JOIN is the mirror of LEFT JOIN - it keeps all rows from the right table. In practice, most developers rewrite RIGHT JOINs as LEFT JOINs by swapping the table order, which reads more naturally.

Show all products and any order_items that reference them - keep products with no sales:

```sql
SELECT p.name, p.category, oi.quantity, oi.unit_price
FROM order_items oi
RIGHT JOIN products p ON oi.product_id = p.product_id
ORDER BY p.name
LIMIT 15;
```

Expected output (yours will differ):

```
      name       |   category   | quantity | unit_price
-----------------+--------------+----------+------------
 Budget Widget   | Electronics  |     NULL |       NULL
 Gadget Plus     | Electronics  |        1 |      49.99
 Gadget Plus     | Electronics  |        2 |      49.99
 Super Cable     | Accessories  |        3 |       9.99
...
```

`Budget Widget` has NULL quantity - it has never been ordered.

---

## 6. CROSS JOIN

A CROSS JOIN produces every possible combination of rows from two tables (Cartesian product). With 5 rows on the left and 4 on the right, you get 20 rows. Use CROSS JOIN deliberately - accidental Cartesian products can generate billions of rows.

Generate all combinations of categories and statuses to build a reporting template:

```sql
SELECT DISTINCT p.category, o.status
FROM products p
CROSS JOIN orders o
ORDER BY p.category, o.status;
```

Expected output (yours will differ):

```
   category   |  status
--------------+-----------
 Accessories  | cancelled
 Accessories  | completed
 Accessories  | pending
 Accessories  | shipped
 Electronics  | cancelled
...
```

This is useful for building a "complete grid" where some cells might have zero values. You will use this pattern in reporting to ensure every category shows up even if it had no orders in a given period.

---

## 7. Self Join

A self join joins a table to itself. This is useful for hierarchical data or comparing rows within the same table.

Find pairs of products in the same category with different prices to spot pricing inconsistencies:

```sql
SELECT p1.name AS product_a, p2.name AS product_b, p1.category, p1.price AS price_a, p2.price AS price_b
FROM products p1
INNER JOIN products p2 ON p1.category = p2.category AND p1.product_id < p2.product_id
ORDER BY p1.category, p1.price
LIMIT 10;
```

Expected output (yours will differ):

```
 product_a   | product_b   |   category   | price_a | price_b
-------------+-------------+--------------+---------+---------
 Super Cable | Laptop Stand| Accessories  |    9.99 |   24.99
 Widget Pro  | Gadget Plus | Electronics  |   29.99 |   49.99
...
(10 rows)
```

The condition `p1.product_id < p2.product_id` prevents duplicate pairs (A+B and B+A) and prevents a product being paired with itself.

---

## 8. Scalar Subqueries

A scalar subquery returns exactly one row and one column. It can appear anywhere an expression can go - in SELECT, WHERE, or HAVING.

Find products priced above the average product price:

```sql
SELECT name, price
FROM products
WHERE price > (SELECT AVG(price) FROM products)
ORDER BY price DESC;
```

Expected output (yours will differ):

```
     name      | price
---------------+--------
 Gadget Plus   |  49.99
 DevKit Pro    |  44.99
...
```

The inner query `(SELECT AVG(price) FROM products)` runs once and returns a single number. The outer query uses that number in its WHERE filter.

Show the average order value next to each order for easy comparison:

```sql
SELECT order_id, total_amount, ROUND((SELECT AVG(total_amount) FROM orders), 2) AS store_avg
FROM orders
ORDER BY total_amount DESC
LIMIT 10;
```

Expected output (yours will differ):

```
 order_id | total_amount | store_avg
----------+--------------+-----------
      287 |       499.95 |    152.74
      134 |       389.97 |    152.74
...
(10 rows)
```

> **Concept: Scalar subquery performance**
> A scalar subquery in the WHERE clause (like the average price example) runs once and its result is reused. A scalar subquery in the SELECT list runs once per row of the outer query unless the planner can optimize it. For large tables, a subquery in the SELECT list can be a performance problem - consider using a CTE or lateral join instead.

---

## 9. Correlated Subqueries

A correlated subquery references a column from the outer query. It runs once per outer row, which can be slow on large tables.

For each customer, find the value of their most recent order:

```sql
SELECT c.name,
       (SELECT MAX(o.total_amount)
        FROM orders o
        WHERE o.customer_id = c.customer_id) AS largest_order
FROM customers c
ORDER BY largest_order DESC NULLS LAST
LIMIT 10;
```

Expected output (yours will differ):

```
     name      | largest_order
---------------+---------------
 Alice Johnson |        499.95
 Bob Smith     |        389.97
 Carol White   |        299.50
...
(10 rows)
```

The inner query references `c.customer_id` from the outer `customers` table. Each time the outer query moves to a new customer row, the inner query re-executes with the new `customer_id`.

> **Concept: Correlated subquery vs JOIN**
> Correlated subqueries are easy to read but execute once per outer row. The same query written as a join with `GROUP BY` often runs faster because the planner can choose a better join strategy. However, correlated subqueries are sometimes the only way to express a "for each row, find the matching X" pattern cleanly.

---

## 10. EXISTS Subquery

`EXISTS` tests whether a subquery returns any rows. It stops as soon as it finds the first match, making it efficient for "does any related row exist?" checks.

Find customers who have placed at least one order:

```sql
SELECT name
FROM customers c
WHERE EXISTS (
  SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id
);
```

Expected output (yours will differ):

```
     name
---------------
 Alice Johnson
 Bob Smith
 Carol White
...
```

Find customers who have never ordered (NOT EXISTS):

```sql
SELECT name
FROM customers c
WHERE NOT EXISTS (
  SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id
);
```

Expected output (yours will differ):

```
     name
--------------
 New Customer
(1 row)
```

Find orders that contain an Electronics product:

```sql
SELECT o.order_id, o.total_amount
FROM orders o
WHERE EXISTS (
  SELECT 1
  FROM order_items oi
  INNER JOIN products p ON oi.product_id = p.product_id
  WHERE oi.order_id = o.order_id AND p.category = 'Electronics'
)
ORDER BY o.total_amount DESC
LIMIT 5;
```

Expected output (yours will differ):

```
 order_id | total_amount
----------+--------------
      287 |       499.95
      134 |       389.97
...
(5 rows)
```

> **Concept: EXISTS vs IN for set membership**
> `WHERE customer_id IN (SELECT customer_id FROM orders)` and `WHERE EXISTS (SELECT 1 FROM orders WHERE ...)` often return identical results. EXISTS is generally faster when the subquery result set is large, because it short-circuits on the first match. IN materializes the full subquery result before the comparison. When NULLs are involved, EXISTS and NOT EXISTS behave more predictably than IN and NOT IN.

---

## 11. Exit

```sql
\q
```

```bash
exit
```

---

## Summary

| Join Type | What It Returns |
|-----------|----------------|
| `INNER JOIN` | Only rows with matches on both sides |
| `LEFT JOIN` | All left rows plus matching right rows (NULLs for no match) |
| `RIGHT JOIN` | All right rows plus matching left rows (NULLs for no match) |
| `CROSS JOIN` | Every combination of rows from both tables |
| Self join | Join a table to itself using two aliases |

| Subquery Type | Characteristic |
|---------------|---------------|
| Scalar | Returns exactly one value; can be used anywhere an expression fits |
| Correlated | References outer query columns; executes once per outer row |
| EXISTS | Tests row existence; stops on first match |

**Next:** Guide 03 covers modifying data with INSERT, UPDATE, DELETE, and UPSERT.
