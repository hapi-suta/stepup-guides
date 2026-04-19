# Exercise 06: Window Functions

**Duration:** 30 minutes
**Objective:** Solve six ranking and running-total problems using window functions. No step-by-step guidance - write the queries from the window function reference in build guide 05.

**Prerequisites:** Build guide 05 (advanced SQL) complete.

---

## Background

Window functions are one of the most powerful SQL features for analytics. Unlike GROUP BY, they preserve all rows while adding computed columns based on nearby rows. Use the `stepup_store` database for all exercises.

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

---

## Problem 3: Running Total of Orders per Customer

For customer_id = 1, show each order in date order with a running cumulative total. Each row should show the individual order amount and the sum of all orders up to and including that one.

Expected columns: `order_id`, `created_at`, `total_amount`, `cumulative_total`

### Answer

```sql
SELECT order_id, created_at, total_amount,
       SUM(total_amount) OVER (ORDER BY created_at, order_id) AS cumulative_total
FROM orders
WHERE customer_id = 1
ORDER BY created_at, order_id;
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

---

## Stretch: 7-Day Moving Average of Daily Revenue

Calculate a 7-day moving average of daily revenue using a window that looks at the current day and the 6 preceding days.

**Hint:** Use `SUM(daily_revenue) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)` and divide by 7.

### Answer

```sql
WITH daily AS (
  SELECT DATE(created_at) AS order_date,
         SUM(total_amount) AS daily_revenue
  FROM orders
  WHERE status = 'completed'
  GROUP BY DATE(created_at)
)
SELECT order_date, daily_revenue,
       ROUND(
         AVG(daily_revenue) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
         2
       ) AS seven_day_avg
FROM daily
ORDER BY order_date;
```

The `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` frame definition tells PostgreSQL to include the current row and the 6 rows before it in the window for each `AVG` calculation.

---

## Exit

```sql
\q
```

```bash
exit
```
