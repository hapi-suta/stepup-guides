# Use Exercise 05 - Plan Cache Analysis with pg_stat_statements

Analyze pg_stat_statements to find queries where planning time is a significant fraction of total time, and understand what that means.

**Server:** NODE1 only

---

## Setup

SSH into NODE1.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

Confirm pg_stat_statements is active (it was enabled in Build Guide 04).

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"
```

Expected output:

```
      extname       | extversion
--------------------+------------
 pg_stat_statements | 1.10
(1 row)
```

If it is missing, create it.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

---

## Step 1 - Reset and Generate Workload

Reset statistics to start clean.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_stat_statements_reset();"
```

Expected output:

```
 pg_stat_statements_reset
--------------------------

(1 row)
```

Connect and run a variety of queries to populate the stats.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Run a simple lookup (fast to plan and execute).

```sql
SELECT customer_id, email FROM customers WHERE customer_id = 1;
SELECT customer_id, email FROM customers WHERE customer_id = 2;
SELECT customer_id, email FROM customers WHERE customer_id = 3;
SELECT customer_id, email FROM customers WHERE customer_id = 4;
SELECT customer_id, email FROM customers WHERE customer_id = 5;
```

Run a complex join that takes more planning time.

```sql
SELECT c.email, p.name, SUM(oi.quantity * oi.unit_price) AS revenue
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.status = 'shipped'
GROUP BY c.email, p.name
HAVING SUM(oi.quantity * oi.unit_price) > 100
ORDER BY revenue DESC;
```

Run it three more times.

```sql
SELECT c.email, p.name, SUM(oi.quantity * oi.unit_price) AS revenue
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.status = 'shipped'
GROUP BY c.email, p.name
HAVING SUM(oi.quantity * oi.unit_price) > 100
ORDER BY revenue DESC;
```

```sql
SELECT c.email, p.name, SUM(oi.quantity * oi.unit_price) AS revenue
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.status = 'shipped'
GROUP BY c.email, p.name
HAVING SUM(oi.quantity * oi.unit_price) > 100
ORDER BY revenue DESC;
```

```sql
SELECT c.email, p.name, SUM(oi.quantity * oi.unit_price) AS revenue
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.status = 'shipped'
GROUP BY c.email, p.name
HAVING SUM(oi.quantity * oi.unit_price) > 100
ORDER BY revenue DESC;
```

Run a medium-complexity query several times.

```sql
SELECT customer_id, COUNT(*), SUM(total_amount) FROM orders GROUP BY customer_id ORDER BY SUM(total_amount) DESC LIMIT 10;
SELECT customer_id, COUNT(*), SUM(total_amount) FROM orders GROUP BY customer_id ORDER BY SUM(total_amount) DESC LIMIT 10;
SELECT customer_id, COUNT(*), SUM(total_amount) FROM orders GROUP BY customer_id ORDER BY SUM(total_amount) DESC LIMIT 10;
```

---

## Step 2 - Find Planning-Heavy Queries

Query pg_stat_statements for queries where mean planning time is a high percentage of mean execution time.

```sql
SELECT
  calls,
  round(mean_plan_time::numeric, 3)  AS avg_plan_ms,
  round(mean_exec_time::numeric, 3)  AS avg_exec_ms,
  round(
    (mean_plan_time / nullif(mean_exec_time + mean_plan_time, 0) * 100)::numeric,
    1
  ) AS plan_pct_of_total,
  left(query, 80) AS query_snippet
FROM pg_stat_statements
WHERE calls > 1
  AND userid = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
ORDER BY mean_plan_time DESC;
```

Expected output (yours will differ):

```
 calls | avg_plan_ms | avg_exec_ms | plan_pct_of_total |              query_snippet
-------+-------------+-------------+-------------------+------------------------------------------
     4 |       0.445 |       1.220 |              26.7 | SELECT c.email, p.name, SUM(oi.quantity *
     3 |       0.088 |       0.312 |              22.0 | SELECT customer_id, COUNT(*), SUM(total_a
     5 |       0.065 |       0.035 |              65.0 | SELECT customer_id, email FROM customers WHERE customer_id
(3 rows)
```

---

## Step 3 - Interpret the Results

Look at the `plan_pct_of_total` column.

**High plan_pct on short queries:** The `SELECT customer_id, email FROM customers WHERE customer_id = $1` query ran 5 times with 65% of total time spent planning. This is common for very fast queries (< 1ms execution). Planning time is basically fixed per query shape, so fast queries show a high planning percentage. This is not a problem - both numbers are tiny.

**High plan_pct on complex queries:** The 4-table join query shows 26.7% planning time. If this query ran thousands of times per second, planning overhead would become meaningful. This is where prepared statements or connection poolers with statement caching help.

---

## Step 4 - Identify the Top Time Consumers

Find the queries consuming the most total time in the system.

```sql
SELECT
  calls,
  round(total_exec_time::numeric, 1) AS total_exec_ms,
  round(total_plan_time::numeric, 1) AS total_plan_ms,
  round((total_exec_time + total_plan_time)::numeric, 1) AS total_ms,
  left(query, 80) AS query_snippet
FROM pg_stat_statements
WHERE userid = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
ORDER BY (total_exec_time + total_plan_time) DESC
LIMIT 5;
```

Expected output (yours will differ):

```
 calls | total_exec_ms | total_plan_ms | total_ms |              query_snippet
-------+---------------+---------------+----------+------------------------------------------
     4 |           4.9 |           1.8 |      6.7 | SELECT c.email, p.name, SUM(oi.quantity *
     3 |           0.9 |           0.3 |      1.2 | SELECT customer_id, COUNT(*), SUM(total_a
     5 |           0.2 |           0.3 |      0.5 | SELECT customer_id, email FROM customers WHERE customer_id
(3 rows)
```

The 4-table join dominates total time even though it only ran 4 times. In production, this view helps you prioritize optimization effort: fix the queries with the highest `total_ms`, not just the highest `avg_ms`.

---

## Step 5 - Find High-Variance Queries (Unstable Plans)

A query with high standard deviation in execution time may have an unstable plan (switching between index scan and seq scan across runs).

```sql
SELECT
  calls,
  round(mean_exec_time::numeric, 3) AS avg_exec_ms,
  round(stddev_exec_time::numeric, 3) AS stddev_exec_ms,
  round((stddev_exec_time / nullif(mean_exec_time, 0))::numeric, 2) AS cv,
  left(query, 80) AS query_snippet
FROM pg_stat_statements
WHERE calls > 2
  AND userid = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
ORDER BY (stddev_exec_time / nullif(mean_exec_time, 0)) DESC NULLS LAST;
```

Expected output (yours will differ):

```
 calls | avg_exec_ms | stddev_exec_ms |  cv  |              query_snippet
-------+-------------+----------------+------+------------------------------------------
     4 |       1.220 |          0.220 | 0.18 | SELECT c.email, p.name, SUM(oi.quantity *
     3 |       0.312 |          0.012 | 0.04 | SELECT customer_id, COUNT(*), SUM(total_a
(2 rows)
```

A coefficient of variation (`cv`) above 0.5 is worth investigating. It could mean the query alternates between a fast index scan and a slow seq scan based on parameter values.

```
\q
```

```
exit
```

---

## Checkpoint

- [ ] You generated mixed workload queries to populate pg_stat_statements
- [ ] You identified which query has the highest planning percentage of total time
- [ ] You identified which query dominates total system time
- [ ] You can explain why a high plan_pct on a fast query is NOT a problem
- [ ] You can explain when high planning time WOULD be a problem and what to do about it
