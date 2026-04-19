# Module 05 - SQL Fundamentals
## Guide 05: Advanced SQL - Window Functions, EXPLAIN, JSON, Arrays

**Objective:** Use window functions for ranking and running totals. Read EXPLAIN ANALYZE output to understand query execution. Query JSONB columns using PostgreSQL operators. Work with arrays.

**Time:** 45-50 minutes

**Prerequisites:**
- Guides 01-04 complete
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

Open psql:

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

## 2. Window Functions

Window functions perform calculations across a set of rows related to the current row - similar to aggregate functions, but without collapsing the rows into one. The result column appears alongside the original row.

### ROW_NUMBER

Assign a sequential number to each product within its category, ordered by price:

```sql
SELECT name, category, price,
       ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS rank_in_category
FROM products
ORDER BY category, price DESC;
```

Expected output (yours will differ):

```
      name      |   category   | price  | rank_in_category
----------------+--------------+--------+------------------
 Laptop Stand   | Accessories  |  24.99 |                1
 Standard Cable | Accessories  |  12.99 |                2
 Super Cable    | Accessories  |   9.99 |                3
 Gadget Plus    | Electronics  |  49.99 |                1
 Widget Pro     | Electronics  |  29.99 |                2
...
```

`PARTITION BY category` restarts the numbering at 1 for each new category. `ORDER BY price DESC` ranks the most expensive product as #1 within each category.

### RANK and DENSE_RANK

`RANK` skips numbers after a tie. `DENSE_RANK` does not skip:

```sql
SELECT name, category, price,
       RANK() OVER (PARTITION BY category ORDER BY price DESC) AS rank_num,
       DENSE_RANK() OVER (PARTITION BY category ORDER BY price DESC) AS dense_rank_num
FROM products
ORDER BY category, price DESC
LIMIT 12;
```

Expected output (yours will differ):

```
      name      |   category   | price  | rank_num | dense_rank_num
----------------+--------------+--------+----------+----------------
 Laptop Stand   | Accessories  |  24.99 |        1 |              1
 Standard Cable | Accessories  |  12.99 |        2 |              2
 Super Cable    | Accessories  |   9.99 |        3 |              3
 Mini Cable     | Accessories  |   9.99 |        3 |              3
 Budget Cable   | Accessories  |   4.99 |        5 |              4
...
```

Two products at $9.99 both get rank 3. `RANK` skips 4 and jumps to 5. `DENSE_RANK` continues with 4.

> **Concept: OVER() defines the window**
> The `OVER()` clause defines the "window" - the set of rows visible to the window function for each row's calculation. `PARTITION BY` divides the result set into groups. `ORDER BY` within `OVER` controls the ordering within each partition. An empty `OVER()` makes the window span the entire result set.

### LAG and LEAD

`LAG` looks at the previous row. `LEAD` looks at the next row. Use them to compare each row to its neighbor.

Show each order's total alongside the previous order for the same customer:

```sql
SELECT customer_id, order_id, total_amount,
       LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY order_id) AS prev_order_amount,
       total_amount - LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY order_id) AS change
FROM orders
WHERE customer_id IN (1, 2)
ORDER BY customer_id, order_id;
```

Expected output (yours will differ):

```
 customer_id | order_id | total_amount | prev_order_amount | change
-------------+----------+--------------+-------------------+---------
           1 |        1 |       125.97 |              NULL |    NULL
           1 |        3 |        89.95 |            125.97 |  -36.02
           1 |        8 |       199.50 |             89.95 |  109.55
           2 |        2 |        49.99 |              NULL |    NULL
           2 |        7 |       299.00 |             49.99 |  249.01
(5 rows)
```

The first order per customer has NULL for `prev_order_amount` because there is no previous row.

### Running Totals

Calculate a cumulative running total of order amounts per customer:

```sql
SELECT customer_id, order_id, total_amount,
       SUM(total_amount) OVER (PARTITION BY customer_id ORDER BY order_id) AS running_total
FROM orders
WHERE customer_id = 1
ORDER BY order_id;
```

Expected output (yours will differ):

```
 customer_id | order_id | total_amount | running_total
-------------+----------+--------------+---------------
           1 |        1 |       125.97 |        125.97
           1 |        3 |        89.95 |        215.92
           1 |        8 |       199.50 |        415.42
(3 rows)
```

`SUM() OVER (PARTITION BY ... ORDER BY ...)` adds each row's amount to the sum of all preceding rows in the partition.

### PERCENT_RANK and NTILE

Find where each order falls in the overall distribution as a percentage:

```sql
SELECT order_id, total_amount,
       ROUND((PERCENT_RANK() OVER (ORDER BY total_amount))::NUMERIC * 100, 1) AS percentile
FROM orders
ORDER BY total_amount DESC
LIMIT 10;
```

Expected output (yours will differ):

```
 order_id | total_amount | percentile
----------+--------------+------------
      287 |       499.95 |      100.0
      134 |       389.97 |       99.3
...
(10 rows)
```

Divide orders into 4 quartiles by total amount:

```sql
SELECT order_id, total_amount,
       NTILE(4) OVER (ORDER BY total_amount) AS quartile
FROM orders
ORDER BY total_amount
LIMIT 20;
```

> **Concept: Window function vs GROUP BY**
> `GROUP BY` collapses rows - you lose the individual row data and see only summary values. Window functions preserve all rows and add new computed columns alongside them. Use `GROUP BY` when you need aggregate results only. Use window functions when you need both individual rows and aggregate context at the same time.

---

## 3. EXPLAIN and EXPLAIN ANALYZE

`EXPLAIN` shows the query plan PostgreSQL intends to use. `EXPLAIN ANALYZE` actually runs the query and shows real execution times.

### Reading a Simple Plan

Explain a simple select:

```sql
EXPLAIN SELECT * FROM products WHERE category = 'Electronics';
```

Expected output (yours will differ):

```
                        QUERY PLAN
-----------------------------------------------------------
 Seq Scan on products  (cost=0.00..1.20 rows=8 width=100)
   Filter: ((category)::text = 'Electronics'::text)
(2 rows)
```

The output has three key numbers in `cost=start..total`:
- `0.00` - startup cost (cost to return the first row)
- `1.20` - total cost (cost to return all rows)
- `rows=8` - estimated number of rows returned
- `width=100` - estimated average bytes per row

`Seq Scan` means PostgreSQL reads every row in the table sequentially. For small tables this is fine.

### EXPLAIN ANALYZE for Timing

Add `ANALYZE` to actually run the query and show real timings:

```sql
EXPLAIN ANALYZE SELECT * FROM products WHERE category = 'Electronics';
```

Expected output (yours will differ):

```
                                            QUERY PLAN
--------------------------------------------------------------------------------------------
 Seq Scan on products  (cost=0.00..1.20 rows=8 width=100) (actual time=0.018..0.025 rows=8 loops=1)
   Filter: ((category)::text = 'Electronics'::text)
   Rows Removed by Filter: 12
 Planning Time: 0.089 ms
 Execution Time: 0.048 ms
(5 rows)
```

`actual time=start..end rows=N loops=L` shows real measurements. `Rows Removed by Filter: 12` tells you how many rows were scanned but discarded.

### EXPLAIN with BUFFERS

Add `BUFFERS` to see cache hits and disk reads:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT o.order_id, c.name, o.total_amount
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.total_amount > 200
ORDER BY o.total_amount DESC;
```

Expected output (yours will differ):

```
 Sort  (cost=25.00..25.50 rows=200 width=60) (actual time=0.450..0.460 rows=85 loops=1)
   Sort Key: o.total_amount DESC
   Sort Method: quicksort  Memory: 32kB
   Buffers: shared hit=12
   ->  Hash Join  (cost=5.00..20.00 rows=200 width=60) (actual time=0.200..0.400 rows=85 loops=1)
         Hash Cond: (o.customer_id = c.customer_id)
         Buffers: shared hit=12
         ->  Seq Scan on orders o  ...
         ->  Hash  (cost=2.50..2.50 rows=50 width=20) (actual time=0.100..0.100 rows=50 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 11kB
               ->  Seq Scan on customers c  ...
```

`shared hit=12` means 12 buffer pages were found in memory (no disk reads). `shared read=N` would indicate disk reads.

> **Concept: Cost units are not milliseconds**
> The `cost` numbers in EXPLAIN are in abstract "cost units" calibrated to a single sequential page read (default = 1.0). They are relative numbers for comparing plan alternatives, not wall-clock time. The actual time in EXPLAIN ANALYZE is real milliseconds. If estimated rows differ greatly from actual rows, the planner's statistics are stale - run `ANALYZE table_name` to refresh them.

---

## 4. JSON and JSONB Operations

PostgreSQL stores JSON in two formats: `JSON` (stores text as-is) and `JSONB` (stores as binary, indexed, slightly slower to write but faster to query). The `audit_log` table uses JSONB.

Check the `audit_log` table structure:

```sql
\d audit_log
```

Expected output (yours will differ):

```
                                     Table "public.audit_log"
   Column    |            Type             | Nullable |         Default
-------------+-----------------------------+----------+-------------------------
 log_id      | integer                     | not null | nextval(...)
 table_name  | character varying(50)       |          |
 operation   | character varying(50)       |          |
 old_data    | jsonb                       |          |
 new_data    | jsonb                       |          |
 changed_by  | character varying(100)      |          |
 changed_at  | timestamp with time zone    | not null | now()
```

View some raw log entries:

```sql
SELECT log_id, table_name, operation, new_data FROM audit_log ORDER BY log_id LIMIT 5;
```

Expected output (yours will differ):

```
 log_id | table_name | operation |                        new_data
--------+------------+-----------+---------------------------------------------------------
      1 | orders     | INSERT    | {"order_id": 1, "customer_id": 5, "total_amount": 125.97}
      2 | orders     | UPDATE    | {"order_id": 1, "status": "completed"}
      3 | products   | UPDATE    | {"product_id": 3, "stock_quantity": 498}
...
```

### Extract a Field with ->

The `->` operator extracts a JSON value and returns it as JSONB:

```sql
SELECT log_id, new_data -> 'order_id' AS order_id
FROM audit_log
WHERE table_name = 'orders' AND operation = 'INSERT'
LIMIT 5;
```

Expected output (yours will differ):

```
 log_id | order_id
--------+----------
      1 | 1
      4 | 2
      9 | 3
```

### Extract as Text with ->>

The `->>` operator extracts a JSON value and returns it as text. Use this when you need to compare or concatenate the value:

```sql
SELECT log_id, new_data ->> 'customer_id' AS customer_id, new_data ->> 'total_amount' AS total
FROM audit_log
WHERE table_name = 'orders' AND operation = 'INSERT'
LIMIT 5;
```

Cast the text result to a numeric type for arithmetic:

```sql
SELECT SUM((new_data ->> 'total_amount')::NUMERIC) AS total_from_logs
FROM audit_log
WHERE table_name = 'orders' AND operation = 'INSERT';
```

Expected output (yours will differ):

```
 total_from_logs
-----------------
        45823.40
(1 row)
```

### Filter by JSON Field Value

Find log entries where the order_id in new_data is 1:

```sql
SELECT log_id, operation, new_data
FROM audit_log
WHERE new_data ->> 'order_id' = '1';
```

Expected output (yours will differ):

```
 log_id | operation |                        new_data
--------+-----------+-----------------------------------------------------------
      1 | INSERT    | {"order_id": 1, "customer_id": 5, "total_amount": 125.97}
      2 | UPDATE    | {"order_id": 1, "status": "completed"}
...
```

Use the `@>` operator (containment) to find rows where the JSONB value contains a specific JSON fragment. This uses a GIN index if one exists:

```sql
SELECT log_id, operation, new_data
FROM audit_log
WHERE new_data @> '{"order_id": 1}';
```

### Check if a Key Exists

The `?` operator tests whether a key exists in the JSONB object:

```sql
SELECT log_id, operation
FROM audit_log
WHERE new_data ? 'total_amount'
LIMIT 5;
```

Expected output (yours will differ):

```
 log_id | operation
--------+-----------
      1 | INSERT
      4 | INSERT
...
```

### Extract Nested JSON

Navigate nested JSON with chained operators. If new_data had a nested object:

```sql
SELECT new_data -> 'metadata' ->> 'source' AS source
FROM audit_log
WHERE new_data -> 'metadata' IS NOT NULL
LIMIT 5;
```

> **Concept: JSONB indexing with GIN**
> JSONB columns support GIN (Generalized Inverted Index) indexing. A GIN index on a JSONB column enables fast `@>` containment and `?` key existence queries. Without an index, every JSON query does a sequential scan. Create one with: `CREATE INDEX idx_audit_new_data ON audit_log USING GIN (new_data);`

---

## 5. Array Operations

PostgreSQL has native array types. You can store and query arrays of any type in a column.

Create a test table with an array column:

```sql
CREATE TABLE IF NOT EXISTS product_tags (
  product_id INTEGER PRIMARY KEY,
  name       VARCHAR(100),
  tags       TEXT[]
);
```

Insert rows with arrays. Array literals use curly braces:

```sql
INSERT INTO product_tags (product_id, name, tags) VALUES
  (1, 'Widget Pro',  ARRAY['sale', 'electronics', 'featured']),
  (2, 'Gadget Plus', ARRAY['electronics', 'new']),
  (3, 'Super Cable', ARRAY['accessories', 'sale']);
```

Select and view the arrays:

```sql
SELECT name, tags FROM product_tags;
```

Expected output:

```
    name     |           tags
-------------+--------------------------
 Widget Pro  | {sale,electronics,featured}
 Gadget Plus | {electronics,new}
 Super Cable | {accessories,sale}
(3 rows)
```

Access a specific array element. Arrays are 1-indexed in PostgreSQL:

```sql
SELECT name, tags[1] AS first_tag FROM product_tags;
```

Expected output:

```
    name     | first_tag
-------------+-----------
 Widget Pro  | sale
 Gadget Plus | electronics
 Super Cable | accessories
(3 rows)
```

Use `@>` (contains) to find products with a specific tag:

```sql
SELECT name, tags FROM product_tags WHERE tags @> ARRAY['sale'];
```

Expected output:

```
    name     |           tags
-------------+--------------------------
 Widget Pro  | {sale,electronics,featured}
 Super Cable | {accessories,sale}
(2 rows)
```

Use `&&` (overlap) to find products with any tag in a given list:

```sql
SELECT name, tags FROM product_tags WHERE tags && ARRAY['sale', 'new'];
```

Use `ANY` to test membership:

```sql
SELECT name FROM product_tags WHERE 'featured' = ANY(tags);
```

Expand an array into rows with `unnest`:

```sql
SELECT name, unnest(tags) AS tag FROM product_tags ORDER BY name, tag;
```

Expected output:

```
    name     |     tag
-------------+-------------
 Gadget Plus | electronics
 Gadget Plus | new
 Super Cable | accessories
 Super Cable | sale
 Widget Pro  | electronics
 Widget Pro  | featured
 Widget Pro  | sale
(7 rows)
```

Cleanup:

```sql
DROP TABLE IF EXISTS product_tags;
```

---

## 6. Exit

```sql
\q
```

```bash
exit
```

---

## Summary

### Window Functions

| Function | Purpose |
|----------|---------|
| `ROW_NUMBER()` | Sequential number, no ties |
| `RANK()` | Rank with gaps on ties |
| `DENSE_RANK()` | Rank without gaps on ties |
| `LAG(col)` | Value from the previous row |
| `LEAD(col)` | Value from the next row |
| `SUM() OVER (... ORDER BY ...)` | Running total |
| `PERCENT_RANK()` | Percentile position 0.0-1.0 |
| `NTILE(n)` | Divide rows into n buckets |

### EXPLAIN Keywords

| Keyword | What It Adds |
|---------|-------------|
| `EXPLAIN` | Show the plan only, do not run |
| `EXPLAIN ANALYZE` | Run the query and show actual times |
| `EXPLAIN (ANALYZE, BUFFERS)` | Also show cache hit/miss counts |

### JSON Operators

| Operator | Returns | Use For |
|----------|---------|---------|
| `->` | JSONB | Extract nested object or array element |
| `->>` | TEXT | Extract value as text for comparison |
| `@>` | BOOLEAN | Containment check (uses GIN index) |
| `?` | BOOLEAN | Key existence check (uses GIN index) |

**Module 05 Build guides complete.** Move to the USE exercises to practice independently.
