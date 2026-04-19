# Module 05 - SQL Fundamentals
## Guide 01: SELECT, Filtering, Aggregation

**Objective:** Learn to retrieve data using SELECT, narrow results with WHERE and ORDER BY, and summarize data with aggregate functions and GROUP BY. All queries run against the `stepup_store` database that the Pulse dashboard app uses.

**Time:** 35-40 minutes

**Prerequisites:**
- SSH access to your lab server as `ec2-user`
- PostgreSQL 16 running on port 5432
- `stepup_store` database populated with products, customers, orders, and order_items

---

## 1. Connect to the Database

Log in to your lab server:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the `postgres` user. This is the database superuser that owns all the objects:

```bash
sudo -iu postgres
```

Open psql connected to the `stepup_store` database. The `-p` flag sets the port (5432) and `-d` sets the target database:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Expected output (yours will differ):

```
psql (16.x)
Type "help" for help.

stepup_store=#
```

You are now at the psql prompt. Every SQL statement must end with a semicolon.

---

## 2. Explore the Schema

Before writing queries, learn what tables and columns exist. The `\dt` command lists tables in the current database:

```sql
\dt
```

Expected output (yours will differ):

```
           List of relations
 Schema |    Name     | Type  |  Owner
--------+-------------+-------+----------
 public | audit_log   | table | postgres
 public | customers   | table | postgres
 public | order_items | table | postgres
 public | orders      | table | postgres
 public | products    | table | postgres
(5 rows)
```

Describe the `products` table to see its columns and data types. The `\d` command shows the structure of any table:

```sql
\d products
```

Expected output (yours will differ):

```
                                        Table "public.products"
    Column     |          Type          | Nullable |            Default
---------------+------------------------+----------+-------------------------------
 product_id    | integer                | not null | nextval('products_product_id_seq')
 name          | character varying(100) | not null |
 category      | character varying(50)  |          |
 price         | numeric(10,2)          | not null |
 stock_qty     | integer                |          | 0
 created_at    | timestamp with time zone | not null | now()
```

Describe the `orders` table the same way:

```sql
\d orders
```

Expected output (yours will differ):

```
                                     Table "public.orders"
    Column    |            Type             | Nullable |         Default
--------------+-----------------------------+----------+-------------------------
 order_id     | integer                     | not null | nextval(...)
 customer_id  | integer                     |          |
 status       | character varying(20)       |          | 'pending'
 total_amount | numeric(10,2)               |          |
 created_at   | timestamp with time zone    | not null | now()
```

> **Concept: Why does column order matter in queries?**
> PostgreSQL stores rows on disk with columns in the order they were defined. When you run `SELECT *`, PostgreSQL returns columns in definition order. In production, always name the columns you need explicitly - `SELECT *` can return sensitive columns or break application code when the schema changes.

---

## 3. Basic SELECT

Fetch all rows from the `products` table. The asterisk `*` is shorthand for "all columns":

```sql
SELECT * FROM products;
```

Expected output (yours will differ):

```
 product_id |       name        |   category    | price  | stock_qty |          created_at
------------+-------------------+---------------+--------+-----------+----------------------------
          1 | Widget Pro        | Electronics   |  29.99 |       150 | 2024-01-15 10:00:00+00
          2 | Gadget Plus       | Electronics   |  49.99 |        75 | 2024-01-15 10:00:00+00
          3 | Super Cable       | Accessories   |   9.99 |       500 | 2024-01-15 10:00:00+00
...
(20 rows)
```

Select only specific columns. Listing column names explicitly is clearer and faster than `SELECT *`:

```sql
SELECT name, category, price FROM products;
```

Expected output (yours will differ):

```
       name        |   category    | price
-------------------+---------------+--------
 Widget Pro        | Electronics   |  29.99
 Gadget Plus       | Electronics   |  49.99
 Super Cable       | Accessories   |   9.99
...
(20 rows)
```

Use column aliases to rename output columns. The `AS` keyword assigns a display name:

```sql
SELECT name AS product_name, price AS unit_price FROM products;
```

Expected output (yours will differ):

```
   product_name    | unit_price
-------------------+------------
 Widget Pro        |      29.99
 Gadget Plus       |      49.99
...
```

---

## 4. Filtering with WHERE

The `WHERE` clause filters rows. Only rows where the condition is true are returned.

Show only products in the Electronics category:

```sql
SELECT name, price FROM products WHERE category = 'Electronics';
```

Expected output (yours will differ):

```
    name     | price
-------------+--------
 Widget Pro  |  29.99
 Gadget Plus |  49.99
...
```

Find products priced above $25. The `>` operator compares numeric values:

```sql
SELECT name, price FROM products WHERE price > 25.00;
```

Expected output (yours will differ):

```
    name     | price
-------------+--------
 Widget Pro  |  29.99
 Gadget Plus |  49.99
...
```

Combine conditions with `AND`. Both conditions must be true for a row to appear:

```sql
SELECT name, price FROM products WHERE category = 'Electronics' AND price < 40.00;
```

Expected output (yours will differ):

```
    name    | price
------------+-------
 Widget Pro | 29.99
```

Use `OR` to match rows where either condition is true:

```sql
SELECT name, category, price FROM products WHERE category = 'Electronics' OR category = 'Accessories';
```

Use `IN` as a cleaner way to match any value in a list:

```sql
SELECT name, category, price FROM products WHERE category IN ('Electronics', 'Accessories');
```

Both queries return the same result. `IN` is easier to read when comparing one column against several values.

Use `BETWEEN` to filter within a range (inclusive on both ends):

```sql
SELECT name, price FROM products WHERE price BETWEEN 10.00 AND 30.00;
```

Expected output (yours will differ):

```
      name      | price
----------------+-------
 Widget Pro     | 29.99
 Standard Cable | 12.99
...
```

Use `LIKE` to match text patterns. The `%` wildcard matches any sequence of characters:

```sql
SELECT name FROM products WHERE name LIKE '%Pro%';
```

Expected output (yours will differ):

```
     name
---------------
 Widget Pro
 DevKit Pro
...
```

> **Concept: Case sensitivity in LIKE**
> `LIKE` is case-sensitive in PostgreSQL. `'%pro%'` will not match `'Widget Pro'`. Use `ILIKE` for case-insensitive pattern matching. This is a PostgreSQL extension - it does not exist in standard SQL.

Filter for NULL values using `IS NULL`. Standard equality (`= NULL`) does not work because NULL is not equal to anything, including itself:

```sql
SELECT name, category FROM products WHERE category IS NULL;
```

Expected output (yours will differ):

```
 name | category
------+----------
(0 rows)
```

---

## 5. Sorting with ORDER BY

Sort products by price from lowest to highest. `ASC` (ascending) is the default:

```sql
SELECT name, price FROM products ORDER BY price ASC;
```

Sort from highest to lowest using `DESC` (descending):

```sql
SELECT name, price FROM products ORDER BY price DESC;
```

Expected output (yours will differ):

```
     name      | price
---------------+--------
 Gadget Plus   |  49.99
 Widget Pro    |  29.99
...
```

Sort by multiple columns. PostgreSQL first sorts by `category`, then by `price` within each category:

```sql
SELECT name, category, price FROM products ORDER BY category ASC, price DESC;
```

Expected output (yours will differ):

```
      name      |   category   | price
----------------+--------------+--------
 Laptop Stand   | Accessories  |  24.99
 Super Cable    | Accessories  |   9.99
 Gadget Plus    | Electronics  |  49.99
 Widget Pro     | Electronics  |  29.99
...
```

---

## 6. Limiting Results with LIMIT and OFFSET

Return only the first 5 rows. `LIMIT` caps the number of rows returned:

```sql
SELECT name, price FROM products ORDER BY price DESC LIMIT 5;
```

Expected output (yours will differ):

```
     name      | price
---------------+--------
 Gadget Plus   |  49.99
 Widget Pro    |  29.99
...
(5 rows)
```

Skip the first 5 rows and return the next 5. `OFFSET` tells PostgreSQL where to start after skipping rows:

```sql
SELECT name, price FROM products ORDER BY price DESC LIMIT 5 OFFSET 5;
```

`LIMIT` with `OFFSET` is the classic pattern for pagination in web applications. Without `ORDER BY`, the "first" and "next" rows are undefined - always combine them.

> **Concept: OFFSET performance on large tables**
> `OFFSET 10000 LIMIT 10` makes PostgreSQL scan and discard the first 10,000 rows before returning 10. On large tables this is slow. Production applications use keyset pagination (WHERE id > last_seen_id) instead.

---

## 7. Aggregate Functions

Aggregate functions collapse multiple rows into a single summary value. Count all products in the table:

```sql
SELECT COUNT(*) FROM products;
```

Expected output:

```
 count
-------
    20
(1 row)
```

Find the total value of all orders. `SUM` adds up all values in a column:

```sql
SELECT SUM(total_amount) FROM orders;
```

Expected output (yours will differ):

```
    sum
-----------
 45823.40
(1 row)
```

Find the highest and lowest product prices:

```sql
SELECT MAX(price) AS highest, MIN(price) AS lowest FROM products;
```

Expected output (yours will differ):

```
 highest | lowest
---------+-------
   49.99 |   4.99
(1 row)
```

Calculate the average order value. `AVG` computes the mean:

```sql
SELECT AVG(total_amount) AS average_order FROM orders;
```

Expected output (yours will differ):

```
    average_order
---------------------
 152.7446666666666667
(1 row)
```

Round the average to 2 decimal places using `ROUND`:

```sql
SELECT ROUND(AVG(total_amount), 2) AS average_order FROM orders;
```

Expected output (yours will differ):

```
 average_order
---------------
        152.74
(1 row)
```

> **Concept: NULL in aggregate functions**
> Aggregate functions (`SUM`, `AVG`, `COUNT(column)`, `MAX`, `MIN`) automatically skip NULL values. `COUNT(*)` counts all rows including those with NULLs. `COUNT(column_name)` counts only non-NULL values in that column. This distinction matters when columns are nullable.

---

## 8. GROUP BY

`GROUP BY` splits rows into groups and runs the aggregate function once per group. Count products by category:

```sql
SELECT category, COUNT(*) AS product_count FROM products GROUP BY category;
```

Expected output (yours will differ):

```
   category   | product_count
--------------+---------------
 Accessories  |             6
 Electronics  |             8
 Software     |             4
 Clothing     |             2
(4 rows)
```

Find the average price per category:

```sql
SELECT category, ROUND(AVG(price), 2) AS avg_price FROM products GROUP BY category ORDER BY avg_price DESC;
```

Expected output (yours will differ):

```
   category   | avg_price
--------------+-----------
 Electronics  |     35.49
 Software     |     24.99
 Accessories  |     14.66
 Clothing     |      9.99
(4 rows)
```

Count orders by status. This shows how many orders are in each pipeline state:

```sql
SELECT status, COUNT(*) AS order_count FROM orders GROUP BY status ORDER BY order_count DESC;
```

Expected output (yours will differ):

```
  status   | order_count
-----------+-------------
 completed |         180
 pending   |          75
 shipped   |          35
 cancelled |          10
(4 rows)
```

> **Concept: GROUP BY rule**
> Every column in your SELECT list must either appear in GROUP BY or be wrapped in an aggregate function. This is because `GROUP BY` collapses multiple rows into one - PostgreSQL does not know which value to show for columns that are not part of the grouping key and not aggregated. This rule is enforced at parse time and will cause an error if violated.

---

## 9. HAVING - Filtering Groups

`WHERE` filters rows before grouping. `HAVING` filters groups after the aggregate is computed.

Show only categories with more than 5 products:

```sql
SELECT category, COUNT(*) AS product_count
FROM products
GROUP BY category
HAVING COUNT(*) > 5;
```

Expected output (yours will differ):

```
   category   | product_count
--------------+---------------
 Electronics  |             8
 Accessories  |             6
(2 rows)
```

Show categories where the average price exceeds $20:

```sql
SELECT category, ROUND(AVG(price), 2) AS avg_price
FROM products
GROUP BY category
HAVING AVG(price) > 20
ORDER BY avg_price DESC;
```

Expected output (yours will differ):

```
   category  | avg_price
-------------+-----------
 Electronics |     35.49
 Software    |     24.99
(2 rows)
```

You can combine WHERE and HAVING. Filter products priced above $5 before grouping, then filter groups with more than 3 members:

```sql
SELECT category, COUNT(*) AS product_count, ROUND(AVG(price), 2) AS avg_price
FROM products
WHERE price > 5.00
GROUP BY category
HAVING COUNT(*) > 3
ORDER BY product_count DESC;
```

> **Concept: SQL execution order**
> SQL statements execute in this logical order: FROM -> WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY -> LIMIT. This is why you cannot use a SELECT alias in a WHERE clause - WHERE runs before SELECT. You can use a SELECT alias in ORDER BY because ORDER BY runs after SELECT. Understanding this order prevents many confusing errors.

---

## 10. Exit

```sql
\q
```

Exit the postgres user session:

```bash
exit
```

---

## Summary

| Clause | Purpose |
|--------|---------|
| `SELECT column` | Choose which columns to return |
| `WHERE condition` | Filter rows before aggregation |
| `ORDER BY column` | Sort results |
| `LIMIT n` | Cap the number of rows returned |
| `OFFSET n` | Skip n rows (used with LIMIT for pagination) |
| `GROUP BY column` | Group rows for aggregate calculation |
| `HAVING condition` | Filter groups after aggregation |
| `COUNT()` | Count rows |
| `SUM()` | Total a numeric column |
| `AVG()` | Average a numeric column |
| `MAX() / MIN()` | Highest or lowest value |

**Next:** Guide 02 covers joins and subqueries - combining data from multiple tables.
