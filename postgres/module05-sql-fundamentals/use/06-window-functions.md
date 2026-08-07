# Exercise 06: Window Functions

**Duration:** 30 minutes
**Objective:** Solve six ranking and running-total problems using window functions. No step-by-step guidance - write the queries from the window function reference in build guide 05.

**Prerequisites:** Build guide 05 (advanced SQL) complete.

---

## Background

Window functions are one of the most powerful SQL features for analytics. Unlike GROUP BY, they preserve all rows while adding computed columns based on nearby rows. Use the `stepup_store` database for all exercises.

Reminder: `orders.status` is one of `pending`, `shipped`, `delivered`, or `cancelled` - there is no `completed` status in this schema.

Connect before starting:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Problem 1: Rank Products by Price Within Category

For every product, show its rank (by price, highest first) within its category. Use `DENSE_RANK` so ties share the same rank with no gaps.

Expected columns: `name`, `category`, `price`, `price_rank`

### Answer

```sql
SELECT name, category, price,
       DENSE_RANK() OVER (PARTITION BY category ORDER BY price DESC) AS price_rank
FROM products
ORDER BY category, price_rank;
```

Expected output:

```
         name         | category | price  | price_rank
----------------------+----------+--------+------------
 PostgreSQL Handbook  | Books    |  49.99 |          1
 Linux Admin Guide    | Books    |  39.99 |          2
 HA Cluster Kit       | Hardware | 599.99 |          1
 Cloud DB Manager     | Software | 249.99 |          1
 Security Scanner     | Software | 219.99 |          2
 DBA Toolkit Pro      | Software | 199.99 |          3
 Data Recovery Pro    | Software | 189.99 |          4
 Migration Tool       | Software | 179.99 |          5
 Replication Toolkit  | Software | 159.99 |          6
 Backup Solution      | Software | 149.99 |          7
 Performance Tuner    | Software | 129.99 |          8
 Monitoring Dashboard | Software |  99.99 |          9
 Database Monitor     | Software |  89.99 |         10
 DBA Certification    | Training | 499.99 |          1
 SQL Mastery Course   | Training | 299.99 |          2
(15 rows)
```

---

## Problem 2: Top Product per Category

Using the ranking from Problem 1 as a base, write a query that returns only the most expensive product in each category. If two products tie for the top price in a category, return both.

**Hint:** Wrap the ranked query in a CTE or subquery and filter where `price_rank = 1`.

### Answer

```sql
WITH ranked AS (
  SELECT name, category, price,
         DENSE_RANK() OVER (PARTITION BY category ORDER BY price DESC) AS price_rank
  FROM products
)
SELECT name, category, price
FROM ranked
WHERE price_rank = 1
ORDER BY category;
```

Expected output:

```
        name        | category | price
---------------------+----------+--------
 PostgreSQL Handbook | Books    |  49.99
 HA Cluster Kit      | Hardware | 599.99
 Cloud DB Manager    | Software | 249.99
 DBA Certification   | Training | 499.99
(4 rows)
```

No category has a price tie in this dataset, so each returns exactly one row.

---

## Problem 3: Running Total of Orders per Customer

For customer_id = 1, show each order in date order with a running cumulative total. Each row should show the individual order amount and the sum of all orders up to and including that one.

Expected columns: `order_id`, `order_date`, `total_amount`, `cumulative_total`

### Answer

```sql
SELECT order_id, order_date, total_amount,
       SUM(total_amount) OVER (ORDER BY order_date, order_id) AS cumulative_total
FROM orders
WHERE customer_id = 1
ORDER BY order_date, order_id;
```

Expected output (yours will differ - order data is randomly generated at provisioning, including which customer has which order_id, so customer_id = 1 may have a different number of orders in your lab):

```
 order_id |         order_date         | total_amount | cumulative_total
----------+----------------------------+--------------+------------------
        9 | 2026-05-26 01:54:36.121303 |       199.99 |           199.99
       36 | 2026-06-22 01:54:36.121303 |       799.96 |           999.95
       24 | 2026-07-18 01:54:36.121303 |       999.95 |          1999.90
(3 rows)
```

---

## Problem 4: Order Amount Change vs Previous Order

For each customer, show how much their order value changed compared to their previous order. Show a positive number for increases and a negative number for decreases.

Expected columns: `customer_id`, `order_id`, `total_amount`, `prev_order_amount`, `change`

Limit to customers 1 through 5.

### Answer

```sql
SELECT customer_id, order_id, total_amount,
       LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY order_id) AS prev_order_amount,
       total_amount - LAG(total_amount) OVER (PARTITION BY customer_id ORDER BY order_id) AS change
FROM orders
WHERE customer_id BETWEEN 1 AND 5
ORDER BY customer_id, order_id;
```

Expected output (yours will differ):

```
 customer_id | order_id | total_amount | prev_order_amount | change
-------------+----------+--------------+--------------------+---------
           1 |        9 |       199.99 |                    |
           1 |       24 |       999.95 |             199.99 |  799.96
           1 |       36 |       799.96 |             999.95 | -199.99
           2 |        3 |       599.97 |                    |
           2 |       32 |       799.96 |             599.97 |  199.99
           2 |       35 |       799.96 |             799.96 |    0.00
...
(17 rows)
```

A `change` of `0.00` (customer 2's orders 32 -> 35 above) simply means two consecutive orders happened to have the identical total - not a bug.

---

## Problem 5: Orders Divided into Quartiles by Revenue

Split all orders into 4 equal groups (quartiles) based on `total_amount`. Show the quartile number and the min/max amount within each quartile.

Two parts:

**Part A** - Assign each order to a quartile:

```sql
SELECT order_id, total_amount,
       NTILE(4) OVER (ORDER BY total_amount) AS quartile
FROM orders
ORDER BY total_amount;
```

**Part B** - Summarize the quartile boundaries:

```sql
WITH quartiled AS (
  SELECT total_amount,
         NTILE(4) OVER (ORDER BY total_amount) AS quartile
  FROM orders
)
SELECT quartile,
       COUNT(*) AS order_count,
       ROUND(MIN(total_amount), 2) AS min_amount,
       ROUND(MAX(total_amount), 2) AS max_amount,
       ROUND(AVG(total_amount), 2) AS avg_amount
FROM quartiled
GROUP BY quartile
ORDER BY quartile;
```

Expected output (yours will differ):

```
 quartile | order_count | min_amount | max_amount | avg_amount
----------+-------------+------------+------------+------------
        1 |          13 |     199.99 |     399.98 |     276.91
        2 |          13 |     599.97 |     599.97 |     599.97
        3 |          12 |     599.97 |     799.96 |     783.29
        4 |          12 |     799.96 |     999.95 |     916.62
(4 rows)
```

With only 5 distinct order totals across 50 orders, quartile boundaries land on repeated values (`599.97` appears in both quartile 2 and quartile 3 here) - `NTILE` still divides the *rows* into 4 groups as evenly as possible (50 rows -> 13/13/12/12), even when the underlying values are not evenly spread.

---

## Problem 6: Each Order's Percentage of Its Customer's Total

For every order, calculate what percentage that order represents of the customer's total lifetime spend.

Expected columns: `order_id`, `customer_id`, `total_amount`, `customer_total`, `pct_of_customer_total`

**Hint:** Use `SUM(total_amount) OVER (PARTITION BY customer_id)` to compute the customer total without GROUP BY.

### Answer

```sql
SELECT order_id, customer_id, total_amount,
       SUM(total_amount) OVER (PARTITION BY customer_id) AS customer_total,
       ROUND(
         total_amount * 100.0 / SUM(total_amount) OVER (PARTITION BY customer_id),
         1
       ) AS pct_of_customer_total
FROM orders
ORDER BY customer_id, order_id;
```

Expected output (yours will differ, truncated to the first 15 rows here):

```
 order_id | customer_id | total_amount | customer_total | pct_of_customer_total
----------+-------------+--------------+-----------------+------------------------
        9 |           1 |       199.99 |         1999.90 |                   10.0
       24 |           1 |       999.95 |         1999.90 |                   50.0
       36 |           1 |       799.96 |         1999.90 |                   40.0
        3 |           2 |       599.97 |         3799.81 |                   15.8
       32 |           2 |       799.96 |         3799.81 |                   21.1
...
```

Every customer's percentages sum to 100.0 (allowing for rounding) - that is a good sanity check to run on your own data.

---

## Stretch: 7-Day Moving Average of Daily Revenue

Calculate a 7-day moving average of daily revenue using a window that looks at the current day and the 6 preceding days. Use `delivered` orders (there is no `completed` status in this schema).

**Hint:** Use `SUM(daily_revenue) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)` and divide by 7 - or use `AVG(...)` over the same frame, which does the division for you automatically based on however many rows are actually in the frame.

### Answer

```sql
WITH daily AS (
  SELECT DATE(order_date) AS order_date,
         SUM(total_amount) AS daily_revenue
  FROM orders
  WHERE status = 'delivered'
  GROUP BY DATE(order_date)
)
SELECT order_date, daily_revenue,
       ROUND(
         AVG(daily_revenue) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
         2
       ) AS seven_day_avg
FROM daily
ORDER BY order_date;
```

Expected output (yours will differ):

```
 order_date | daily_revenue | seven_day_avg
------------+----------------+---------------
 2026-05-10 |         399.98 |        399.98
 2026-05-12 |         799.96 |        599.97
 2026-05-13 |         799.96 |        666.63
 2026-05-16 |         799.96 |        699.97
 2026-05-20 |         799.96 |        719.96
 2026-06-01 |        1199.94 |        799.96
 2026-06-05 |         799.96 |        799.96
...
```

The `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` frame definition tells PostgreSQL to include the current row and up to the 6 rows before it in the window for each `AVG` calculation. Note this is a 7-*row* window over distinct order days, not a strict 7-*calendar-day* window - if there are gaps between order days (as there likely are here, since orders are sparse), the average blends days that are further apart than a week. A true calendar-based moving average would need a `RANGE` frame over an actual date interval instead of `ROWS`.

---

## Exit

```sql
\q
```

```bash
exit
```
