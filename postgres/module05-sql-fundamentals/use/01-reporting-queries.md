# Exercise 01: Business Reporting Queries

**Duration:** 25 minutes
**Objective:** Write five business-level queries against the `stepup_store` database using joins, aggregation, and filtering - without step-by-step hand-holding.

**Prerequisites:** Build guides 01 and 02 complete.

---

## Background

The Pulse dashboard team has asked you to produce five reports from the `stepup_store` database. You have the schema knowledge from the build guides. Write each query, run it, and verify the output makes sense.

Connect before starting:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Query 1: Top 5 Customers by Lifetime Spend

**Business question:** Which five customers have spent the most money across all completed orders?

**Requirements:**
- Include only orders with `status = 'completed'`
- Show: customer name, number of orders, total lifetime spend, average order value
- Round monetary values to 2 decimal places
- Order by total spend descending

Write and run the query. Verify that the top customer's spend is the sum of all their completed order totals.

### Answer

```sql
SELECT c.name,
       COUNT(o.order_id) AS order_count,
       ROUND(SUM(o.total_amount), 2) AS lifetime_spend,
       ROUND(AVG(o.total_amount), 2) AS avg_order_value
FROM customers c
INNER JOIN orders o ON c.customer_id = o.customer_id
WHERE o.status = 'completed'
GROUP BY c.customer_id, c.name
ORDER BY lifetime_spend DESC
LIMIT 5;
```

---

## Query 2: Daily Revenue Trend (Last 30 Days)

**Business question:** What was the revenue for each day over the last 30 days, ordered from oldest to newest?

**Requirements:**
- Group by calendar day
- Show: date, number of orders that day, total revenue that day
- Include only completed orders
- Use `DATE(order_date)` to truncate to the day
- Show only days that had at least one order

Write and run the query. Check that totals per day look reasonable given your data.

### Answer

```sql
SELECT DATE(order_date) AS order_day,
       COUNT(*) AS orders_that_day,
       ROUND(SUM(total_amount), 2) AS daily_revenue
FROM orders
WHERE status = 'completed'
  AND order_date >= now() - INTERVAL '30 days'
GROUP BY DATE(order_date)
ORDER BY order_day ASC;
```

---

## Query 3: Product Performance Report

**Business question:** Which products generated the most revenue? Show the top 10 by total revenue across all order_items.

**Requirements:**
- Join order_items to products
- Show: product name, category, total units sold, total revenue (quantity * unit_price)
- Include all orders regardless of status
- Order by total revenue descending

Write and run the query. Verify that unit_price in order_items may differ from the current products.price (prices may have changed since the order was placed - use order_items.unit_price for historical revenue).

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

---

## Stretch: Combine Queries 1 and 3

Write a single query that shows the top 5 customers AND for each customer, their most purchased product category (by quantity).

This is harder - think about using CTEs or subqueries to compute each piece separately before joining them.
