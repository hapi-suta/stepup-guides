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

Expected output:

```
         name         | category | price  | rank_in_category
----------------------+----------+--------+------------------
 PostgreSQL Handbook  | Books    |  49.99 |                1
 Linux Admin Guide    | Books    |  39.99 |                2
 HA Cluster Kit       | Hardware | 599.99 |                1
 Cloud DB Manager     | Software | 249.99 |                1
 Security Scanner     | Software | 219.99 |                2
 DBA Toolkit Pro      | Software | 199.99 |                3
...
 DBA Certification    | Training | 499.99 |                1
 SQL Mastery Course   | Training | 299.99 |                2
(15 rows)
```

`PARTITION BY category` restarts the numbering at 1 for each new category. `ORDER BY price DESC` ranks the most expensive product as #1 within each category.

### RANK and DENSE_RANK

`RANK` skips numbers after a tie. `DENSE_RANK` does not skip. This dataset has no exact price ties, so both columns match here - the difference only shows up when two rows share a price.

```sql
SELECT name, category, price,
       RANK() OVER (PARTITION BY category ORDER BY price DESC) AS rank_num,
       DENSE_RANK() OVER (PARTITION BY category ORDER BY price DESC) AS dense_rank_num
FROM products
ORDER BY category, price DESC
LIMIT 12;
```

Expected output:

```
         name         | category | price  | rank_num | dense_rank_num
----------------------+----------+--------+----------+----------------
 PostgreSQL Handbook  | Books    |  49.99 |        1 |              1
 Linux Admin Guide    | Books    |  39.99 |        2 |              2
 HA Cluster Kit       | Hardware | 599.99 |        1 |              1
 Cloud DB Manager     | Software | 249.99 |        1 |              1
 Security Scanner     | Software | 219.99 |        2 |              2
 DBA Toolkit Pro      | Software | 199.99 |        3 |              3
 Data Recovery Pro    | Software | 189.99 |        4 |              4
 Migration Tool       | Software | 179.99 |        5 |              5
 Replication Toolkit  | Software | 159.99 |        6 |              6
 Backup Solution      | Software | 149.99 |        7 |              7
 Performance Tuner    | Software | 129.99 |        8 |              8
 Monitoring Dashboard | Software |  99.99 |        9 |              9
(12 rows)
```

> **Concept: OVER() defines the window**
> The `OVER()` clause defines the "window" - the set of rows visible to the window function for each row's calculation. `PARTITION BY` divides the result set into groups. `ORDER BY` within `OVER` controls the ordering within each partition. An empty `OVER()` makes the window span the entire result set. If two rows tie on the ORDER BY column, `RANK` gives them the same rank and skips the next number; `DENSE_RANK` gives them the same rank without skipping.

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

Expected output (yours will differ - order data is randomly generated at provisioning):

```
 customer_id | order_id | total_amount | prev_order_amount | change
-------------+----------+--------------+--------------------+---------
           1 |        9 |       199.99 |                    |
           1 |       24 |       999.95 |             199.99 |  799.96
           1 |       36 |       799.96 |             999.95 | -199.99
           2 |        3 |       599.97 |                    |
           2 |       32 |       799.96 |             599.97 |  199.99
...
(8 rows)
```

The first order per customer has NULL (blank) for `prev_order_amount` because there is no previous row.

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
           1 |        9 |       199.99 |        199.99
           1 |       24 |       999.95 |       1199.94
           1 |       36 |       799.96 |       1999.90
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
       24 |       999.95 |       87.8
       38 |       999.95 |       87.8
       33 |       999.95 |       87.8
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
EXPLAIN SELECT * FROM products WHERE category = 'Software';
```

Expected output:

```
                       QUERY PLAN
----------------------------------------------------------
 Seq Scan on products  (cost=0.00..1.19 rows=1 width=368)
   Filter: ((category)::text = 'Software'::text)
(2 rows)
```

The output has three key numbers in `cost=start..total`:
- `0.00` - startup cost (cost to return the first row)
- `1.19` - total cost (cost to return all rows)
- `rows=1` - estimated number of rows returned
- `width=368` - estimated average bytes per row

`Seq Scan` means PostgreSQL reads every row in the table sequentially. For small tables this is fine - and note the estimate of `rows=1` is quite wrong (there are actually 10 Software products). That is expected on a freshly loaded table before statistics have been gathered.

### EXPLAIN ANALYZE for Timing

Add `ANALYZE` to actually run the query and show real timings:

```sql
EXPLAIN ANALYZE SELECT * FROM products WHERE category = 'Software';
```

Expected output:

```
                                            QUERY PLAN
---------------------------------------------------------------------------------------------------
 Seq Scan on products  (cost=0.00..1.19 rows=1 width=368) (actual time=0.005..0.007 rows=10 loops=1)
   Filter: ((category)::text = 'Software'::text)
   Rows Removed by Filter: 5
 Planning Time: 0.027 ms
 Execution Time: 0.013 ms
(5 rows)
```

`actual time=start..end rows=N loops=L` shows real measurements. `Rows Removed by Filter: 5` tells you how many of the 15 rows were scanned but discarded (the 5 non-Software products). Notice the gap between the estimate (`rows=1`) and the actual (`rows=10`) - this is exactly the stale-statistics scenario described below. Running `ANALYZE products;` would tighten that estimate.

### EXPLAIN with BUFFERS

Add `BUFFERS` to see cache hits and disk reads:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT o.order_id, c.first_name || ' ' || c.last_name AS customer_name, o.total_amount
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.total_amount > 200
ORDER BY o.total_amount DESC;
```

Expected output (yours will differ in row counts - orders data is randomized at provisioning):

```
 Sort  (cost=16.00..16.11 rows=42 width=43) (actual time=0.076..0.078 rows=42 loops=1)
   Sort Key: o.total_amount DESC
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=2
   ->  Hash Join  (cost=12.93..14.87 rows=42 width=43) (actual time=0.038..0.057 rows=42 loops=1)
         Hash Cond: (o.customer_id = c.customer_id)
         Buffers: shared hit=2
         ->  Seq Scan on orders o  (cost=0.00..1.62 rows=42 width=15) (actual time=0.005..0.012 rows=42 loops=1)
               Filter: (total_amount > '200'::numeric)
               Rows Removed by Filter: 8
               Buffers: shared hit=1
         ->  Hash  (cost=11.30..11.30 rows=130 width=240) (actual time=0.017..0.017 rows=10 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 9kB
               Buffers: shared hit=1
               ->  Seq Scan on customers c  (cost=0.00..11.30 rows=130 width=240) (actual time=0.003..0.004 rows=10 loops=1)
                     Buffers: shared hit=1
 Planning Time: 0.238 ms
 Execution Time: 0.094 ms
```

`shared hit=1` means 1 buffer page was found in memory (no disk reads). `shared read=N` would indicate disk reads. On tables this small, everything fits in a single page or two, which is why every count is tiny.

> **Concept: Cost units are not milliseconds**
> The `cost` numbers in EXPLAIN are in abstract "cost units" calibrated to a single sequential page read (default = 1.0). They are relative numbers for comparing plan alternatives, not wall-clock time. The actual time in EXPLAIN ANALYZE is real milliseconds. If estimated rows differ greatly from actual rows, the planner's statistics are stale - run `ANALYZE table_name` to refresh them.

---

## 4. JSON and JSONB Operations

PostgreSQL stores JSON in two formats: `JSON` (stores text as-is) and `JSONB` (stores as binary, indexed, slightly slower to write but faster to query). `stepup_store` does not ship with a pre-built audit table, so this section builds one - `audit_log_demo` - to practice against. In a real system, a table like this is usually populated by an application layer or a trigger that snapshots the old and new row on every change.

Create the demo table:

```sql
CREATE TABLE audit_log_demo (
  log_id      SERIAL PRIMARY KEY,
  table_name  VARCHAR(50),
  operation   VARCHAR(20),
  old_data    JSONB,
  new_data    JSONB,
  changed_by  VARCHAR(100),
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Check its structure:

```sql
\d audit_log_demo
```

Expected output:

```
                                    Table "public.audit_log_demo"
   Column   |           Type           | Nullable |                    Default
------------+--------------------------+----------+------------------------------------------------
 log_id     | integer                  | not null | nextval('audit_log_demo_log_id_seq'::regclass)
 table_name | character varying(50)    |          |
 operation  | character varying(20)    |          |
 old_data   | jsonb                    |          |
 new_data   | jsonb                    |          |
 changed_by | character varying(100)   |          |
 changed_at | timestamp with time zone | not null | now()
```

Seed it with a few representative events - three new orders, two status changes on the same order, one cancellation, and one product update with a nested `metadata` object:

```sql
INSERT INTO audit_log_demo (table_name, operation, new_data, changed_by, changed_at) VALUES
  ('orders', 'INSERT', '{"order_id": 101, "customer_id": 3, "total_amount": 249.99, "status": "pending"}', 'app_service', now() - interval '5 days'),
  ('orders', 'INSERT', '{"order_id": 102, "customer_id": 7, "total_amount": 89.99,  "status": "pending"}', 'app_service', now() - interval '4 days 20 hours'),
  ('orders', 'INSERT', '{"order_id": 103, "customer_id": 3, "total_amount": 599.99, "status": "pending"}', 'app_service', now() - interval '4 days 2 hours');

INSERT INTO audit_log_demo (table_name, operation, old_data, new_data, changed_by, changed_at) VALUES
  ('orders', 'UPDATE', '{"order_id": 101, "status": "pending"}', '{"order_id": 101, "status": "shipped"}', 'fulfillment_bot', now() - interval '3 days'),
  ('orders', 'UPDATE', '{"order_id": 101, "status": "shipped"}', '{"order_id": 101, "status": "delivered"}', 'fulfillment_bot', now() - interval '1 day'),
  ('orders', 'UPDATE', '{"order_id": 102, "status": "pending"}', '{"order_id": 102, "status": "cancelled"}', 'support_agent', now() - interval '2 days');

INSERT INTO audit_log_demo (table_name, operation, new_data, changed_by, changed_at) VALUES
  ('products', 'UPDATE', '{"product_id": 6, "stock": 15, "metadata": {"source": "warehouse_sync"}}', 'inventory_sync', now() - interval '6 hours');
```

View the raw log entries:

```sql
SELECT log_id, table_name, operation, new_data FROM audit_log_demo ORDER BY log_id LIMIT 5;
```

Expected output (JSONB reorders keys internally - shortest key first, so do not expect insertion order back):

```
 log_id | table_name | operation |                                     new_data
--------+------------+-----------+------------------------------------------------------------------------------------
      1 | orders     | INSERT    | {"status": "pending", "order_id": 101, "customer_id": 3, "total_amount": 249.99}
      2 | orders     | INSERT    | {"status": "pending", "order_id": 102, "customer_id": 7, "total_amount": 89.99}
      3 | orders     | INSERT    | {"status": "pending", "order_id": 103, "customer_id": 3, "total_amount": 599.99}
      4 | orders     | UPDATE    | {"status": "shipped", "order_id": 101}
      5 | orders     | UPDATE    | {"status": "delivered", "order_id": 101}
(5 rows)
```

### Extract a Field with ->

The `->` operator extracts a JSON value and returns it as JSONB:

```sql
SELECT log_id, new_data -> 'order_id' AS order_id
FROM audit_log_demo
WHERE table_name = 'orders' AND operation = 'INSERT'
LIMIT 5;
```

Expected output:

```
 log_id | order_id
--------+----------
      1 | 101
      2 | 102
      3 | 103
(3 rows)
```

### Extract as Text with ->>

The `->>` operator extracts a JSON value and returns it as text. Use this when you need to compare or concatenate the value:

```sql
SELECT log_id, new_data ->> 'customer_id' AS customer_id, new_data ->> 'total_amount' AS total
FROM audit_log_demo
WHERE table_name = 'orders' AND operation = 'INSERT'
LIMIT 5;
```

Expected output:

```
 log_id | customer_id | total
--------+-------------+--------
      1 | 3           | 249.99
      2 | 7           | 89.99
      3 | 3           | 599.99
(3 rows)
```

Cast the text result to a numeric type for arithmetic:

```sql
SELECT SUM((new_data ->> 'total_amount')::NUMERIC) AS total_from_logs
FROM audit_log_demo
WHERE table_name = 'orders' AND operation = 'INSERT';
```

Expected output:

```
 total_from_logs
-----------------
          939.97
(1 row)
```

### Filter by JSON Field Value

Find log entries where the order_id in new_data is 101:

```sql
SELECT log_id, operation, new_data
FROM audit_log_demo
WHERE new_data ->> 'order_id' = '101';
```

Expected output:

```
 log_id | operation |                                     new_data
--------+-----------+------------------------------------------------------------------------------------
      1 | INSERT    | {"status": "pending", "order_id": 101, "customer_id": 3, "total_amount": 249.99}
      4 | UPDATE    | {"status": "shipped", "order_id": 101}
      5 | UPDATE    | {"status": "delivered", "order_id": 101}
(3 rows)
```

Use the `@>` operator (containment) to find rows where the JSONB value contains a specific JSON fragment. This can use a GIN index if one exists:

```sql
SELECT log_id, operation, new_data
FROM audit_log_demo
WHERE new_data @> '{"order_id": 101}';
```

Returns the same 3 rows as above - `@>` checks that the JSON fragment on the right is contained within the column's JSON on the left.

### Check if a Key Exists

The `?` operator tests whether a key exists in the JSONB object:

```sql
SELECT log_id, operation
FROM audit_log_demo
WHERE new_data ? 'total_amount'
LIMIT 5;
```

Expected output:

```
 log_id | operation
--------+-----------
      1 | INSERT
      2 | INSERT
      3 | INSERT
(3 rows)
```

Only the three INSERT events carry a `total_amount` key - the UPDATE events only recorded `order_id` and `status`.

### Extract Nested JSON

Navigate nested JSON with chained operators. The `products` UPDATE event has a nested `metadata` object:

```sql
SELECT new_data -> 'metadata' ->> 'source' AS source
FROM audit_log_demo
WHERE new_data -> 'metadata' IS NOT NULL
LIMIT 5;
```

Expected output:

```
     source
----------------
 warehouse_sync
(1 row)
```

`->` (returns JSONB) drills into the `metadata` object, then `->>` (returns text) extracts its `source` field as a plain string.

### GIN Indexing

```sql
EXPLAIN SELECT log_id, new_data FROM audit_log_demo WHERE new_data @> '{"status": "cancelled"}';
```

Expected output:

```
                          QUERY PLAN
----------------------------------------------------------------
 Seq Scan on audit_log_demo  (cost=0.00..12.00 rows=2 width=36)
   Filter: (new_data @> '{"status": "cancelled"}'::jsonb)
(2 rows)
```

Create a GIN (Generalized Inverted Index) index, which speeds up `@>` containment and `?` key-existence queries on JSONB columns:

```sql
CREATE INDEX idx_audit_log_demo_new_data ON audit_log_demo USING GIN (new_data);
```

Run EXPLAIN again:

```sql
EXPLAIN SELECT log_id, new_data FROM audit_log_demo WHERE new_data @> '{"status": "cancelled"}';
```

Expected output:

```
                         QUERY PLAN
---------------------------------------------------------------
 Seq Scan on audit_log_demo  (cost=0.00..1.09 rows=1 width=36)
   Filter: (new_data @> '{"status": "cancelled"}'::jsonb)
(2 rows)
```

With only 7 rows in the table, the planner still chooses a sequential scan even though the GIN index exists - scanning 7 rows directly is cheaper than the overhead of an index lookup. This is an important real-world lesson: **creating an index does not guarantee PostgreSQL will use it.** The planner is cost-based. A GIN index on `new_data` earns its keep once the table has thousands or millions of rows, where scanning every row sequentially becomes far more expensive than an index lookup.

Clean up the demo table:

```sql
DROP TABLE IF EXISTS audit_log_demo;
```

> **Concept: JSONB indexing with GIN**
> JSONB columns support GIN indexing. A GIN index on a JSONB column enables fast `@>` containment and `?` key existence queries at scale. Without an index, every JSON query does a sequential scan. On a small table the planner may still prefer a sequential scan regardless of the index - always verify with EXPLAIN rather than assuming an index is being used.

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
  (2, 'DBA Toolkit Pro',    ARRAY['sale', 'software', 'featured']),
  (6, 'HA Cluster Kit',     ARRAY['hardware', 'new']),
  (11, 'Linux Admin Guide', ARRAY['books', 'sale']);
```

Select and view the arrays:

```sql
SELECT name, tags FROM product_tags ORDER BY product_id;
```

Expected output:

```
       name        |           tags
-------------------+--------------------------
 DBA Toolkit Pro   | {sale,software,featured}
 HA Cluster Kit    | {hardware,new}
 Linux Admin Guide | {books,sale}
(3 rows)
```

Access a specific array element. Arrays are 1-indexed in PostgreSQL:

```sql
SELECT name, tags[1] AS first_tag FROM product_tags ORDER BY product_id;
```

Expected output:

```
       name        | first_tag
-------------------+-----------
 DBA Toolkit Pro   | sale
 HA Cluster Kit    | hardware
 Linux Admin Guide | books
(3 rows)
```

Use `@>` (contains) to find products with a specific tag:

```sql
SELECT name, tags FROM product_tags WHERE tags @> ARRAY['sale'];
```

Expected output:

```
       name        |           tags
-------------------+--------------------------
 DBA Toolkit Pro   | {sale,software,featured}
 Linux Admin Guide | {books,sale}
(2 rows)
```

Use `&&` (overlap) to find products with any tag in a given list:

```sql
SELECT name, tags FROM product_tags WHERE tags && ARRAY['sale', 'new'];
```

Expected output:

```
       name        |           tags
-------------------+--------------------------
 DBA Toolkit Pro   | {sale,software,featured}
 HA Cluster Kit    | {hardware,new}
 Linux Admin Guide | {books,sale}
(3 rows)
```

Use `ANY` to test membership:

```sql
SELECT name FROM product_tags WHERE 'featured' = ANY(tags);
```

Expected output:

```
      name
-----------------
 DBA Toolkit Pro
(1 row)
```

Expand an array into rows with `unnest`:

```sql
SELECT name, unnest(tags) AS tag FROM product_tags ORDER BY name, tag;
```

Expected output:

```
       name        |   tag
-------------------+----------
 DBA Toolkit Pro   | featured
 DBA Toolkit Pro   | sale
 DBA Toolkit Pro   | software
 HA Cluster Kit    | hardware
 HA Cluster Kit    | new
 Linux Admin Guide | books
 Linux Admin Guide | sale
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
| `@>` | BOOLEAN | Containment check (uses GIN index at scale) |
| `?` | BOOLEAN | Key existence check (uses GIN index at scale) |

**Module 05 Build guides complete.** Move to the USE exercises to practice independently.
