# Guide 04 - Query Optimization

Learn the most common SQL anti-patterns that kill performance, how to rewrite them, and how to use pg_stat_statements to find your slowest queries in production.

**Server:** NODE1 only

---

## What You Will Learn

- Five anti-patterns: SELECT *, missing WHERE, implicit type casts, OR vs UNION ALL, subquery vs JOIN
- How each anti-pattern damages query performance and how to fix it
- How to enable and use pg_stat_statements to find slow queries

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

---

## 2. Anti-Pattern 1: SELECT * Fetches Columns You Do Not Need

`SELECT *` retrieves every column from every row, including large text fields, JSON blobs, and binary data. It prevents Index-Only Scans and inflates network transfer.

Bad query.

```sql
EXPLAIN ANALYZE SELECT * FROM customers WHERE customer_id = 42;
```

Expected output (yours will differ):

```
                                                        QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------
 Index Scan using customers_pkey on customers  (cost=0.29..8.30 rows=1 width=57) (actual time=0.010..0.010 rows=1 loops=1)
   Index Cond: (customer_id = 42)
 Planning Time: 0.337 ms
 Execution Time: 0.047 ms
(4 rows)
```

Note the `width=57` - PostgreSQL is fetching 57 bytes per row even if you only need email and name.

Good query - fetch only what the application needs.

```sql
EXPLAIN ANALYZE SELECT customer_id, email, name FROM customers WHERE customer_id = 42;
```

Expected output (yours will differ):

```
                                                        QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------
 Index Scan using customers_pkey on customers  (cost=0.29..8.30 rows=1 width=37) (actual time=0.007..0.008 rows=1 loops=1)
   Index Cond: (customer_id = 42)
 Planning Time: 0.031 ms
 Execution Time: 0.016 ms
(4 rows)
```

`width` dropped from 57 to 37. Same result, less data transferred per row.

> **Concept - SELECT * in Production**: SELECT * also creates fragile code. When a column is added or renamed, application code that destructures positional columns breaks silently. Always name your columns explicitly in queries that run in production.

---

## 3. Anti-Pattern 2: Missing WHERE on Large Tables

A query without a WHERE clause forces a full table scan every time. On a growing table this becomes catastrophic.

```sql
EXPLAIN ANALYZE SELECT order_id, total_amount FROM orders;
```

Expected output (yours will differ):

```
                                                QUERY PLAN
-----------------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..968.00 rows=50000 width=10) (actual time=0.005..5.302 rows=50000 loops=1)
 Planning Time: 0.065 ms
 Execution Time: 6.883 ms
(3 rows)
```

With 50,000 rows this already takes ~7ms. At 10 million rows this query takes seconds.

Good practice: always filter to the data you need.

```sql
EXPLAIN ANALYZE
SELECT order_id, total_amount
FROM orders
WHERE order_date >= NOW() - INTERVAL '30 days'
  AND status = 'pending';
```

Expected output (yours will differ):

```
                                               QUERY PLAN
---------------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..1468.00 rows=1101 width=10) (actual time=0.007..7.092 rows=957 loops=1)
   Filter: (((status)::text = 'pending'::text) AND (order_date >= (now() - '30 days'::interval)))
   Rows Removed by Filter: 49043
 Planning Time: 0.103 ms
 Execution Time: 7.138 ms
(5 rows)
```

Even though this is still a Seq Scan (no index on these columns yet), the filtered query returns far fewer rows than the full table scan. In Guide 02 you will learn how to create indexes that speed this up further.

---

## 4. Anti-Pattern 3: Implicit Type Casts Defeat Indexes

When you compare a column to a value of a different data type, PostgreSQL must cast one side. If the cast is applied to the indexed column, the index cannot be used.

Check the data type of customer_id.

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'orders' AND column_name = 'customer_id';
```

Expected output:

```
 column_name | data_type
-------------+-----------
 customer_id | integer
(1 row)
```

Bad query - comparing integer column to a text value.

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = '5';
```

Expected output (yours will differ):

```
                                                         QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------
 Index Scan using orders_customer_id_idx on orders  (cost=0.14..8.22 rows=2 width=72) (actual time=0.025..0.031 rows=2 loops=1)
   Index Cond: (customer_id = 5)
 Planning Time: 0.108 ms
 Execution Time: 0.044 ms
(4 rows)
```

PostgreSQL is smart enough to cast `'5'` to integer here. But this is unreliable for other types. A more dangerous case is casting a stored varchar to integer.

```sql
EXPLAIN ANALYZE SELECT * FROM customers WHERE lower(email) = lower('ALICE@EXAMPLE.COM');
```

Expected output (yours will differ):

```
                              QUERY PLAN
------------------------------------------------------------------------
 Seq Scan on customers  (cost=0.00..6.00 rows=1 width=80) (actual time=0.018..0.105 rows=1 loops=1)
   Filter: (lower((email)::text) = 'alice@example.com')
   Rows Removed by Filter: 199
 Planning Time: 0.072 ms
 Execution Time: 0.116 ms
(5 rows)
```

The expression index on `lower(email)` exists but is NOT used because `lower(email) = lower('...')` does not match the index expression `lower(email)`. The right side must be a constant.

Good query - move the function to the constant side.

```sql
EXPLAIN ANALYZE SELECT * FROM customers WHERE lower(email) = 'alice@example.com';
```

Expected output (yours will differ):

```
                                                            QUERY PLAN
------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_customers_email_lower on customers  (cost=0.14..8.16 rows=1 width=80) (actual time=0.031..0.034 rows=1 loops=1)
   Index Cond: (lower((email)::text) = 'alice@example.com')
 Planning Time: 0.188 ms
 Execution Time: 0.048 ms
(4 rows)
```

> **Concept - Function on Indexed Column**: The rule is: never wrap an indexed column in a function on the left side of a comparison unless you have an expression index for that exact function. `WHERE date(order_date) = '2024-01-01'` defeats an index on `order_date`. Rewrite it as `WHERE order_date >= '2024-01-01' AND order_date < '2024-01-02'`.

---

## 5. Anti-Pattern 4: OR Prevents Index Usage (Use UNION ALL)

An OR condition across different columns often forces a Seq Scan because PostgreSQL cannot use a single index for both conditions efficiently.

```sql
EXPLAIN ANALYZE
SELECT * FROM customers
WHERE email = 'alice@example.com' OR name = 'Alice';
```

Expected output (yours will differ):

```
                              QUERY PLAN
------------------------------------------------------------------------
 Seq Scan on customers  (cost=0.00..6.00 rows=2 width=80) (actual time=0.014..0.088 rows=2 loops=1)
   Filter: ((email = 'alice@example.com') OR ((name)::text = 'Alice'))
   Rows Removed by Filter: 198
 Planning Time: 0.077 ms
 Execution Time: 0.098 ms
(5 rows)
```

Rewrite with UNION ALL - each branch can use its own index.

```sql
EXPLAIN ANALYZE
SELECT * FROM customers WHERE email = 'alice@example.com'
UNION ALL
SELECT * FROM customers WHERE name = 'Alice'
  AND email != 'alice@example.com';
```

Expected output (yours will differ):

```
                                                             QUERY PLAN
--------------------------------------------------------------------------------------------------------------------------------------
 Append  (cost=0.14..17.00 rows=2 width=80) (actual time=0.028..0.059 rows=2 loops=1)
   ->  Index Scan using customers_email_idx on customers  (cost=0.14..8.16 rows=1 width=80) ...
   ->  Index Scan using customers_name_idx on customers  (cost=0.14..8.18 rows=1 width=80) ...
 Planning Time: 0.220 ms
 Execution Time: 0.074 ms
(6 rows)
```

Each branch uses its own index scan. The `AND email != 'alice@example.com'` deduplicates overlap between the two sets.

Note: use `UNION` (not `UNION ALL`) if duplicates would be a problem, but UNION ALL is faster because it skips the deduplication step.

---

## 6. Anti-Pattern 5: Correlated Subquery vs JOIN

A correlated subquery runs once for every row in the outer query. A JOIN computes the relationship once.

Bad query - correlated subquery runs 200 times (once per customer).

```sql
EXPLAIN ANALYZE
SELECT c.email,
  (SELECT SUM(total_amount) FROM orders o WHERE o.customer_id = c.customer_id) AS lifetime_spend
FROM customers c;
```

Expected output (yours will differ):

```
                                                    QUERY PLAN
------------------------------------------------------------------------------------------------------------------
 Seq Scan on customers c  (cost=0.00..1306.00 rows=200 width=44) (actual time=0.018..1.245 rows=200 loops=1)
   SubPlan 1
     ->  Aggregate  (cost=6.50..6.51 rows=1 width=32) (actual time=0.006..0.006 rows=1 loops=200)
           ->  Seq Scan on orders o  (cost=0.00..12.50 rows=2 width=12) ...
 Planning Time: 0.112 ms
 Execution Time: 1.288 ms
(6 rows)
```

The `loops=200` inside SubPlan 1 means the inner query ran 200 times.

Good query - rewrite as a JOIN with aggregation.

```sql
EXPLAIN ANALYZE
SELECT c.email, COALESCE(SUM(o.total_amount), 0) AS lifetime_spend
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.email;
```

Expected output (yours will differ):

```
                                                 QUERY PLAN
-------------------------------------------------------------------------------------------------------------
 HashAggregate  (cost=28.50..33.50 rows=200 width=44) (actual time=0.412..0.445 rows=200 loops=1)
   Group Key: c.customer_id
   ->  Hash Left Join  (cost=14.50..26.50 rows=200 width=20) (actual time=0.085..0.284 rows=200 loops=1)
         Hash Cond: (o.customer_id = c.customer_id)
         ->  Seq Scan on orders o  (cost=0.00..12.50 rows=50 width=12) ...
         ->  Hash  (cost=5.00..5.00 rows=200 width=12) ...
               ->  Seq Scan on customers c ...
 Planning Time: 0.185 ms
 Execution Time: 0.488 ms
(9 rows)
```

No `loops=200`. The join processes both tables once. The LEFT JOIN ensures customers with no orders still appear with a 0.

> **Concept - When Subqueries Are OK**: Scalar subqueries in SELECT are usually correlated and should be rewritten as JOINs. But subqueries in FROM (derived tables) are not correlated - they run once and are fine. `SELECT * FROM (SELECT customer_id, COUNT(*) FROM orders GROUP BY customer_id) AS sub WHERE count > 5` is efficient.

---

## 7. Enable pg_stat_statements

`pg_stat_statements` records execution statistics for every query. It is the fastest way to find the slowest queries in a production database.

Enable the extension (requires a restart - it must be listed in `shared_preload_libraries`).

```
\q
```

```
exit
```

```
sudo vi /opt/pgsql/data/postgresql.conf
```

Find the `shared_preload_libraries` line and add `pg_stat_statements`.

```
shared_preload_libraries = 'pg_stat_statements'
```

Save and exit vi (`:wq`).

Restart PostgreSQL to load the library.

```
sudo systemctl restart postgresql-16
```

Switch to postgres and create the extension.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

Expected output:

```
CREATE EXTENSION
```

---

## 8. Find Slow Queries with pg_stat_statements

Run some queries to populate the view.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT * FROM orders WHERE status = 'pending';"
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT c.email, SUM(o.total_amount) FROM customers c LEFT JOIN orders o ON o.customer_id = c.customer_id GROUP BY c.customer_id, c.email;"
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT * FROM order_items WHERE order_id = 10;"
```

Now query pg_stat_statements to find the slowest queries by total time.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT
  round(total_exec_time::numeric, 2) AS total_ms,
  calls,
  round(mean_exec_time::numeric, 2) AS avg_ms,
  round(stddev_exec_time::numeric, 2) AS stddev_ms,
  left(query, 60) AS query_snippet
FROM pg_stat_statements
WHERE userid = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):

```
 total_ms | calls | avg_ms | stddev_ms |              query_snippet
----------+-------+--------+-----------+------------------------------------------
    12.45 |     3 |   4.15 |      0.22 | SELECT c.email, SUM(o.total_amount) FROM
     3.21 |     2 |   1.61 |      0.08 | SELECT * FROM orders WHERE status = $1
     0.88 |     1 |   0.88 |      0.00 | SELECT * FROM order_items WHERE order_id
(3 rows)
```

> **Concept - Normalized Queries**: pg_stat_statements normalizes queries - it replaces literal values with `$1`, `$2` placeholders. This means `WHERE id = 5` and `WHERE id = 99` are counted as the same query. This is intentional: you care about the query pattern, not the specific values.

Find queries where planning time is high relative to execution time.

```sql
SELECT
  round(mean_plan_time::numeric, 2) AS avg_plan_ms,
  round(mean_exec_time::numeric, 2) AS avg_exec_ms,
  calls,
  left(query, 60) AS query_snippet
FROM pg_stat_statements
WHERE calls > 0
ORDER BY mean_plan_time DESC
LIMIT 5;
```

Expected output (yours will differ):

```
 avg_plan_ms | avg_exec_ms | calls |              query_snippet
-------------+-------------+-------+------------------------------------------
        0.22 |        4.15 |     3 | SELECT c.email, SUM(o.total_amount) FROM
        0.12 |        0.05 |     2 | SELECT * FROM orders WHERE status = $1
(2 rows)
```

When `avg_plan_ms` is consistently more than 10% of `avg_exec_ms`, the planner is spending too long choosing a plan. This often indicates missing statistics or overly complex queries.

Reset the statistics to start fresh.

```sql
SELECT pg_stat_statements_reset();
```

Expected output:

```
 pg_stat_statements_reset
--------------------------

(1 row)
```

```
\q
```

```
exit
```

---

## Checkpoint

By the end of this guide you should be able to:

- [ ] Identify and fix SELECT * anti-pattern with targeted column lists
- [ ] Explain why implicit type casts defeat indexes and how to fix them
- [ ] Rewrite an OR query as UNION ALL to allow per-branch index usage
- [ ] Rewrite a correlated subquery as a JOIN
- [ ] Enable pg_stat_statements and query it to find the top 10 slowest queries

---

**Proceed to:** [Guide 05 - Checkpoint and WAL Tuning](./05-checkpoint-wal-tuning.md)
