# Exercise 01: Business Reporting Queries

**Duration:** 25 minutes
**Objective:** Write five business-level queries against the `stepup_store` database using joins, aggregation, and filtering - without step-by-step hand-holding.

**Prerequisites:** Build guides 01 and 02 complete.

---

## Background

The Pulse dashboard team has asked you to produce five reports from the `stepup_store` database. You have the schema knowledge from the build guides. Write each query, run it, and verify the output makes sense.

Reminder: `customers` has separate `first_name` and `last_name` columns, not a single `name` column. `orders.status` is one of `pending`, `shipped`, `delivered`, or `cancelled` - there is no `completed` status in this schema. Use `delivered` wherever the business question below says "completed orders."

Connect before starting:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Query 1: Top 5 Customers by Lifetime Spend

**Business question:** Which five customers have spent the most money across all delivered orders?

**Requirements:**
- Include only orders with `status = 'delivered'`
- Show: customer name, number of orders, total lifetime spend, average order value
- Round monetary values to 2 decimal places
- Order by total spend descending

Write and run the query. Verify that the top customer's spend is the sum of all their delivered order totals.

### Answer

```sql
SELECT c.first_name || ' ' || c.last_name AS name,
       COUNT(o.order_id) AS order_count,
       ROUND(SUM(o.total_amount), 2) AS lifetime_spend,
       ROUND(AVG(o.total_amount), 2) AS avg_order_value
FROM customers c
INNER JOIN orders o ON c.customer_id = o.customer_id
WHERE o.status = 'delivered'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY lifetime_spend DESC
LIMIT 5;
```

Expected output (yours will differ - order data is randomly generated at provisioning):

```
    name     | order_count | lifetime_spend | avg_order_value
-------------+-------------+----------------+-----------------
 Grace Lee   |           4 |        2999.85 |          749.96
 Frank Brown |           3 |        2199.89 |          733.30
 Hank Miller |           3 |        1399.93 |          466.64
 Bob Smith   |           2 |        1399.93 |          699.97
 Iris Garcia |           1 |         799.96 |          799.96
(5 rows)
```

If fewer than 5 customers have a delivered order in your data, you will see fewer than 5 rows - that is correct behavior for an INNER JOIN with a WHERE filter, not a bug.

---

## Query 2: Daily Revenue Trend (Last 30 Days)

**Business question:** What was the revenue for each day over the last 30 days, ordered from oldest to newest?

**Requirements:**
- Group by calendar day
- Show: date, number of orders that day, total revenue that day
- Include only delivered orders
- Use `DATE(order_date)` to truncate to the day
- Show only days that had at least one order

Write and run the query. Check that totals per day look reasonable given your data.

### Answer

```sql
SELECT DATE(order_date) AS order_day,
       COUNT(*) AS orders_that_day,
       ROUND(SUM(total_amount), 2) AS daily_revenue
FROM orders
WHERE status = 'delivered'
  AND order_date >= now() - INTERVAL '30 days'
GROUP BY DATE(order_date)
ORDER BY order_day ASC;
```

Expected output (yours will differ - this can legitimately return 0 rows):

```
 order_day | orders_that_day | daily_revenue
-----------+-----------------+---------------
(0 rows)
```

The seeded orders are spread randomly across the last 90 days. It is entirely possible - and happened in this run - that none of the `delivered` orders happen to fall within the last 30 days. A query returning 0 rows is not automatically a bug; check that the WHERE clause and join conditions are correct, then trust the result. To see the full 90-day picture instead, temporarily widen the interval to `'90 days'` and rerun.

---

## Query 3: Product Performance Report

**Business question:** Which products generated the most revenue? Show the top 10 by total revenue across all order_items.

**Requirements:**
- Join order_items to products
- Show: product name, category, total units sold, total revenue (quantity * unit_price)
- Include all orders regardless of status
- Order by total revenue descending

Write and run the query.

### Answer

```sql
SELECT p.name, p.category,
       SUM(oi.quantity) AS units_sold,
       ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_revenue
FROM products p
INNER JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY p.product_id, p.name, p.category
ORDER BY total_revenue DESC
LIMIT 10;
```

Expected output (yours will differ):

```
        name         | category | units_sold | total_revenue
---------------------+----------+------------+---------------
 Database Monitor    | Software |         21 |       4199.79
 Replication Toolkit | Software |         21 |       4199.79
 HA Cluster Kit       | Hardware |         14 |       2799.86
 Cloud DB Manager     | Software |         14 |       2799.86
 SQL Mastery Course   | Training |         13 |       2599.87
...
(10 rows)
```

> **Data quality note:** In this seed data, every `order_items.unit_price` happens to be `199.99` regardless of which product it references - a known quirk of the random data generator used when your lab was provisioned. That means `total_revenue` here reflects `quantity * 199.99`, not each product's real `price`. The query pattern is still correct SQL for the "historical price at time of sale" concept described in `products.price` vs `order_items.unit_price` - just be aware the numbers in this particular dataset do not vary by product the way they would in a real system.

---

## Query 4: Category Revenue Breakdown with Percentage

**Business question:** What share of total revenue does each product category represent?

**Requirements:**
- Show: category, total revenue for that category, percentage of all revenue
- Round the percentage to 1 decimal place
- Order by percentage descending
- Include all order statuses

Hint: You need the total revenue for all categories to calculate the percentage. A subquery or window function will help.

### Answer

```sql
SELECT p.category,
       ROUND(SUM(oi.quantity * oi.unit_price), 2) AS category_revenue,
       ROUND(
         SUM(oi.quantity * oi.unit_price) * 100.0 /
         SUM(SUM(oi.quantity * oi.unit_price)) OVER (),
         1
       ) AS pct_of_total
FROM products p
INNER JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY p.category
ORDER BY category_revenue DESC;
```

Expected output (yours will differ):

```
 category | category_revenue | pct_of_total
----------+-------------------+--------------
 Software |          19399.03 |         61.0
 Training |           5199.74 |         16.4
 Books    |           4399.78 |         13.8
 Hardware |           2799.86 |          8.8
(4 rows)
```

`SUM(SUM(oi.quantity * oi.unit_price)) OVER ()` is a window function wrapped around an aggregate: the inner `SUM` computes revenue per category (the GROUP BY level), and the outer `SUM() OVER ()` adds all of those category totals together to get the grand total, without collapsing the rows.

---

## Query 5: Order Velocity by Hour of Day

**Business question:** At what hours of the day do most orders come in? This helps schedule customer support staffing.

**Requirements:**
- Extract the hour from `order_date` using `EXTRACT(HOUR FROM order_date)`
- Show: hour (0-23), number of orders at that hour
- All order statuses
- Order by order count descending so the busiest hours are at the top

### Answer

```sql
SELECT EXTRACT(HOUR FROM order_date)::INT AS hour_of_day,
       COUNT(*) AS order_count
FROM orders
GROUP BY hour_of_day
ORDER BY order_count DESC;
```

Expected output (yours will differ):

```
 hour_of_day | order_count
-------------+-------------
           1 |          50
(1 row)
```

The lab's data generator only randomizes the *day* each order was placed, not the time of day - every order keeps the same hour:minute:second as the moment your lab was provisioned. That is why you will likely see a single hour with all 50 orders rather than a spread across the day. The query itself is the correct pattern for this analysis; a real production `orders` table with genuinely random timestamps would show a realistic distribution across hours.

---

## Exit

```sql
\q
```

```bash
exit
```

---

## Stretch: Combine Queries 1 and 3

Write a single query that shows the top 5 customers AND for each customer, their most purchased product category (by quantity).

This is harder - think about using CTEs or subqueries to compute each piece separately before joining them.
