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

Expected output:

```
            List of relations
 Schema |    Name     | Type  |  Owner
--------+-------------+-------+----------
 public | customers   | table | postgres
 public | order_items | table | postgres
 public | orders      | table | postgres
 public | products    | table | postgres
(4 rows)
```

Describe the `products` table to see its columns and data types. The `\d` command shows the structure of any table:

```sql
\d products
```

Expected output:

```
                                    Table "public.products"
   Column   |          Type          | Nullable |                   Default
------------+------------------------+----------+-----------------------------------------------
 product_id | integer                | not null | nextval('products_product_id_seq'::regclass)
 name       | character varying(100) | not null |
 category   | character varying(50)  |          |
 price      | numeric(10,2)          | not null |
 stock      | integer                |          | 0
 created_at | timestamp without time zone |     | now()
```

Describe the `orders` table the same way:

```sql
\d orders
```

Expected output:

```
                                   Table "public.orders"
    Column    |            Type             | Nullable |                 Default
--------------+-----------------------------+----------+------------------------------------------
 order_id     | integer                     | not null | nextval('orders_order_id_seq'::regclass)
 customer_id  | integer                     |          |
 order_date   | timestamp without time zone |          | now()
 status       | character varying(20)       |          | 'pending'::character varying
 total_amount | numeric(10,2)               |          |
```

> **Concept: Why does column order matter in queries?**
> PostgreSQL stores rows on disk with columns in the order they were defined. When you run `SELECT *`, PostgreSQL returns columns in definition order. In production, always name the columns you need explicitly - `SELECT *` can return sensitive columns or break application code when the schema changes.

---

## 3. Basic SELECT

Fetch all rows from the `products` table. The asterisk `*` is shorthand for "all columns":

```sql
SELECT * FROM products;
```

Expected output:

```
 product_id |         name         | category | price  | stock |         created_at
------------+----------------------+----------+--------+-------+----------------------------
          1 | PostgreSQL Handbook  | Books    |  49.99 |   100 | 2026-08-07 01:54:36.119072
          2 | DBA Toolkit Pro      | Software | 199.99 |    50 | 2026-08-07 01:54:36.119072
          3 | Database Monitor     | Software |  89.99 |    75 | 2026-08-07 01:54:36.119072
...
(15 rows)
```

Select only specific columns. Listing column names explicitly is clearer and faster than `SELECT *`:

```sql
SELECT name, category, price FROM products;
```

Expected output:

```
         name         | category | price
----------------------+----------+--------
 PostgreSQL Handbook  | Books    |  49.99
 DBA Toolkit Pro      | Software | 199.99
 Database Monitor     | Software |  89.99
...
(15 rows)
```

Use column aliases to rename output columns. The `AS` keyword assigns a display name:

```sql
SELECT name AS product_name, price AS unit_price FROM products LIMIT 5;
```

Expected output:

```
    product_name     | unit_price
---------------------+------------
 PostgreSQL Handbook  |      49.99
 DBA Toolkit Pro      |     199.99
 Database Monitor     |      89.99
 SQL Mastery Course   |     299.99
 Backup Solution      |     149.99
(5 rows)
```

---

## 4. Filtering with WHERE

The `WHERE` clause filters rows. Only rows where the condition is true are returned.

Show only products in the Software category:

```sql
SELECT name, price FROM products WHERE category = 'Software';
```

Expected output:

```
         name         | price
----------------------+--------
 DBA Toolkit Pro      | 199.99
 Database Monitor     |  89.99
 Backup Solution      | 149.99
 Performance Tuner    | 129.99
 Migration Tool       | 179.99
 Monitoring Dashboard |  99.99
 Cloud DB Manager     | 249.99
 Replication Toolkit  | 159.99
 Security Scanner     | 219.99
 Data Recovery Pro    | 189.99
(10 rows)
```

Find products priced above $200. The `>` operator compares numeric values:

```sql
SELECT name, price FROM products WHERE price > 200.00 ORDER BY price DESC;
```

Expected output:

```
        name        | price
---------------------+--------
 HA Cluster Kit      | 599.99
 DBA Certification   | 499.99
 SQL Mastery Course  | 299.99
 Cloud DB Manager    | 249.99
 Security Scanner    | 219.99
(5 rows)
```

Combine conditions with `AND`. Both conditions must be true for a row to appear:

```sql
SELECT name, price FROM products WHERE category = 'Software' AND price < 100.00;
```

Expected output:

```
         name         | price
----------------------+-------
 Database Monitor     | 89.99
 Monitoring Dashboard | 99.99
(2 rows)
```

Use `OR` to match rows where either condition is true:

```sql
SELECT name, category, price FROM products WHERE category = 'Books' OR category = 'Hardware' ORDER BY category, price;
```

Expected output:

```
        name         | category | price
---------------------+----------+--------
 Linux Admin Guide   | Books    |  39.99
 PostgreSQL Handbook | Books    |  49.99
 HA Cluster Kit      | Hardware | 599.99
(3 rows)
```

Use `IN` as a cleaner way to match any value in a list:

```sql
SELECT name, category, price FROM products WHERE category IN ('Books', 'Hardware') ORDER BY category, price;
```

Both queries return the same result. `IN` is easier to read when comparing one column against several values.

Use `BETWEEN` to filter within a range (inclusive on both ends):

```sql
SELECT name, price FROM products WHERE price BETWEEN 40.00 AND 150.00 ORDER BY price;
```

Expected output:

```
         name         | price
----------------------+--------
 PostgreSQL Handbook  |  49.99
 Database Monitor     |  89.99
 Monitoring Dashboard |  99.99
 Performance Tuner    | 129.99
 Backup Solution      | 149.99
(5 rows)
```

Use `LIKE` to match text patterns. The `%` wildcard matches any sequence of characters:

```sql
SELECT name FROM products WHERE name LIKE '%Pro%';
```

Expected output:

```
      name
------------------
 DBA Toolkit Pro
 Data Recovery Pro
(2 rows)
```

> **Concept: Case sensitivity in LIKE**
> `LIKE` is case-sensitive in PostgreSQL. `'%pro%'` will not match `'DBA Toolkit Pro'`. Use `ILIKE` for case-insensitive pattern matching. This is a PostgreSQL extension - it does not exist in standard SQL.

Filter for NULL values using `IS NULL`. Standard equality (`= NULL`) does not work because NULL is not equal to anything, including itself:

```sql
SELECT name, category FROM products WHERE category IS NULL;
```

Expected output:

```
 name | category
------+----------
(0 rows)
```

Every seeded product has a category, so this returns no rows - that itself is useful information about data completeness.

---

## 5. Sorting with ORDER BY

Sort products by price from lowest to highest. `ASC` (ascending) is the default:

```sql
SELECT name, price FROM products ORDER BY price ASC;
```

Expected output (truncated):

```
         name         | price
----------------------+--------
 Linux Admin Guide    |  39.99
 PostgreSQL Handbook  |  49.99
 Database Monitor     |  89.99
...
(15 rows)
```

Sort from highest to lowest using `DESC` (descending):

```sql
SELECT name, price FROM products ORDER BY price DESC;
```

Expected output (truncated):

```
        name        | price
---------------------+--------
 HA Cluster Kit      | 599.99
 DBA Certification   | 499.99
 SQL Mastery Course  | 299.99
...
(15 rows)
```

Sort by multiple columns. PostgreSQL first sorts by `category`, then by `price` within each category:

```sql
SELECT name, category, price FROM products ORDER BY category ASC, price DESC;
```

Expected output (truncated):

```
         name         | category | price
----------------------+----------+--------
 PostgreSQL Handbook  | Books    |  49.99
 Linux Admin Guide    | Books    |  39.99
 HA Cluster Kit       | Hardware | 599.99
 Cloud DB Manager     | Software | 249.99
...
(15 rows)
```

---

## 6. Limiting Results with LIMIT and OFFSET

Return only the first 5 rows. `LIMIT` caps the number of rows returned:

```sql
SELECT name, price FROM products ORDER BY price DESC LIMIT 5;
```

Expected output:

```
        name        | price
---------------------+--------
 HA Cluster Kit      | 599.99
 DBA Certification   | 499.99
 SQL Mastery Course  | 299.99
 Cloud DB Manager    | 249.99
 Security Scanner    | 219.99
(5 rows)
```

Skip the first 5 rows and return the next 5. `OFFSET` tells PostgreSQL where to start after skipping rows:

```sql
SELECT name, price FROM products ORDER BY price DESC LIMIT 5 OFFSET 5;
```

Expected output:

```
        name         | price
---------------------+--------
 DBA Toolkit Pro     | 199.99
 Data Recovery Pro   | 189.99
 Migration Tool      | 179.99
 Replication Toolkit | 159.99
 Backup Solution     | 149.99
(5 rows)
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
    15
(1 row)
```

Find the total value of all orders. `SUM` adds up all values in a column:

```sql
SELECT SUM(total_amount) FROM orders;
```

Expected output (yours will differ - order data is randomly generated when your lab is provisioned):

```
   sum
----------
 31798.41
(1 row)
```

Find the highest and lowest product prices:

```sql
SELECT MAX(price) AS highest, MIN(price) AS lowest FROM products;
```

Expected output:

```
 highest | lowest
---------+--------
  599.99 |  39.99
(1 row)
```

Calculate the average order value. `AVG` computes the mean:

```sql
SELECT AVG(total_amount) AS average_order FROM orders;
```

Expected output (yours will differ):

```
    average_order
----------------------
 635.9682000000000000
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
        635.97
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

Expected output:

```
 category | product_count
----------+---------------
 Books    |             2
 Hardware |             1
 Software |            10
 Training |             2
(4 rows)
```

Find the average price per category:

```sql
SELECT category, ROUND(AVG(price), 2) AS avg_price FROM products GROUP BY category ORDER BY avg_price DESC;
```

Expected output:

```
 category | avg_price
----------+-----------
 Hardware |    599.99
 Training |    399.99
 Software |    166.99
 Books    |     44.99
(4 rows)
```

Count orders by status. This shows how many orders are in each pipeline state:

```sql
SELECT status, COUNT(*) AS order_count FROM orders GROUP BY status ORDER BY order_count DESC;
```

Expected output (yours will differ - order status is assigned randomly at provisioning):

```
  status   | order_count
-----------+-------------
 pending   |          15
 delivered |          15
 cancelled |          11
 shipped   |           9
(4 rows)
```

Note there is no `completed` status in this schema - the four possible values are `pending`, `shipped`, `delivered`, and `cancelled`.

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

Expected output:

```
 category | product_count
----------+---------------
 Software |            10
(1 row)
```

Show categories where the average price exceeds $200:

```sql
SELECT category, ROUND(AVG(price), 2) AS avg_price
FROM products
GROUP BY category
HAVING AVG(price) > 200
ORDER BY avg_price DESC;
```

Expected output:

```
 category | avg_price
----------+-----------
 Hardware |    599.99
 Training |    399.99
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

Expected output:

```
 category | product_count | avg_price
----------+---------------+-----------
 Software |            10 |    166.99
(1 row)
```

Every product in this dataset costs more than $5, so the `WHERE` clause here does not remove any rows in this case - but it still demonstrates that `WHERE` runs before `GROUP BY`.

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
