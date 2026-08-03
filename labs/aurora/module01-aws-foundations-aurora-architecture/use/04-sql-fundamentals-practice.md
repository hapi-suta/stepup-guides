# Exercise 04: SQL Fundamentals Practice

**Duration:** 35 minutes
**Objective:** Practice core SQL skills through 10 exercises of increasing difficulty using a realistic e-commerce database schema. These are skills you will use daily when managing Aurora PostgreSQL.
**Prerequisites:** Module 01 BUILD guides complete, connected to your Aurora PostgreSQL cluster via psql

---

## Background

You are the new DBA at [COMPANY], an online bookstore. Your first task is to set up the database schema, load sample data, and answer questions from the business team using SQL queries.

Connect to your Aurora cluster before starting. All commands run inside psql.

---

## Setup: Create the Schema and Load Data

Run this SQL block in psql to create the tables and load sample data. Read through the table structure carefully - you will need to understand it for the exercises.

```sql
-- Create the bookstore schema
CREATE SCHEMA IF NOT EXISTS bookstore;
SET search_path TO bookstore;

-- Customers table
CREATE TABLE customers (
    customer_id    SERIAL PRIMARY KEY,
    first_name     VARCHAR(50) NOT NULL,
    last_name      VARCHAR(50) NOT NULL,
    email          VARCHAR(100) UNIQUE NOT NULL,
    city           VARCHAR(50),
    state          VARCHAR(2),
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Books table
CREATE TABLE books (
    book_id        SERIAL PRIMARY KEY,
    title          VARCHAR(200) NOT NULL,
    author         VARCHAR(100) NOT NULL,
    genre          VARCHAR(50),
    price          NUMERIC(8,2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0,
    published_year INTEGER
);

-- Orders table
CREATE TABLE orders (
    order_id       SERIAL PRIMARY KEY,
    customer_id    INTEGER REFERENCES customers(customer_id),
    order_date     DATE NOT NULL DEFAULT CURRENT_DATE,
    status         VARCHAR(20) DEFAULT 'pending',
    total_amount   NUMERIC(10,2)
);

-- Order items (line items in each order)
CREATE TABLE order_items (
    item_id        SERIAL PRIMARY KEY,
    order_id       INTEGER REFERENCES orders(order_id),
    book_id        INTEGER REFERENCES books(book_id),
    quantity       INTEGER NOT NULL DEFAULT 1,
    unit_price     NUMERIC(8,2) NOT NULL
);

-- Insert sample customers
INSERT INTO customers (first_name, last_name, email, city, state) VALUES
('Alice',   'Johnson',  'alice.j@email.com',    'Austin',       'TX'),
('Bob',     'Smith',    'bob.smith@email.com',   'Seattle',      'WA'),
('Carol',   'Davis',    'carol.d@email.com',     'Portland',     'OR'),
('David',   'Wilson',   'david.w@email.com',     'Austin',       'TX'),
('Eve',     'Brown',    'eve.brown@email.com',   'New York',     'NY'),
('Frank',   'Taylor',   'frank.t@email.com',     'Seattle',      'WA'),
('Grace',   'Anderson', 'grace.a@email.com',     'Chicago',      'IL'),
('Henry',   'Thomas',   'henry.t@email.com',     'Portland',     'OR'),
('Irene',   'Martinez', 'irene.m@email.com',     'Austin',       'TX'),
('Jack',    'Garcia',   'jack.g@email.com',      'New York',     'NY');

-- Insert sample books
INSERT INTO books (title, author, genre, price, stock_quantity, published_year) VALUES
('PostgreSQL Deep Dive',         'Sarah Chen',       'Technical',    49.99,  120, 2024),
('Aurora in Production',         'Mike Roberts',     'Technical',    39.99,   85, 2023),
('SQL Patterns',                 'Sarah Chen',       'Technical',    34.99,  200, 2022),
('The Data Warehouse Toolkit',   'Ralph Kimball',    'Technical',    59.99,   45, 2013),
('Database Reliability',         'Laine Campbell',   'Technical',    44.99,   60, 2021),
('Clean Code',                   'Robert Martin',    'Software',     37.99,  150, 2008),
('The Pragmatic Programmer',     'Dave Thomas',      'Software',     42.99,  100, 2019),
('Designing Data Systems',       'Martin Kleppmann', 'Architecture', 47.99,   90, 2017),
('Site Reliability Engineering', 'Betsy Beyer',      'Operations',   54.99,   70, 2016),
('The Phoenix Project',          'Gene Kim',         'Operations',   29.99,  180, 2013);

-- Insert sample orders
INSERT INTO orders (customer_id, order_date, status, total_amount) VALUES
(1,  '2025-01-15', 'completed',  89.98),
(1,  '2025-03-20', 'completed',  49.99),
(2,  '2025-02-10', 'completed',  77.98),
(3,  '2025-02-28', 'completed',  34.99),
(4,  '2025-03-05', 'shipped',    97.98),
(5,  '2025-03-10', 'completed', 134.97),
(5,  '2025-04-01', 'pending',    42.99),
(6,  '2025-01-20', 'completed',  44.99),
(7,  '2025-04-15', 'shipped',    84.98),
(8,  '2025-03-25', 'completed',  29.99),
(2,  '2025-04-20', 'pending',    59.99),
(9,  '2025-05-01', 'pending',    39.99);

-- Insert sample order items
INSERT INTO order_items (order_id, book_id, quantity, unit_price) VALUES
(1,  1, 1, 49.99),
(1,  3, 1, 34.99),
(1,  6, 1,  5.00),
(2,  1, 1, 49.99),
(3,  2, 1, 39.99),
(3,  6, 1, 37.99),
(4,  3, 1, 34.99),
(5,  4, 1, 59.99),
(5,  6, 1, 37.99),
(6,  8, 1, 47.99),
(6,  9, 1, 54.99),
(6,  3, 1, 31.99),
(7,  7, 1, 42.99),
(8,  5, 1, 44.99),
(9,  1, 1, 49.99),
(9,  3, 1, 34.99),
(10, 10, 1, 29.99),
(11, 4, 1, 59.99),
(12, 2, 1, 39.99);
```

Expected output (yours will differ):
```
CREATE SCHEMA
SET
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
INSERT 0 10
INSERT 0 10
INSERT 0 12
INSERT 0 19
```

---

## Exercise 1: Basic SELECT (Easy)

**Business question:** "Show me all books in stock with their titles, authors, and prices, sorted by price from highest to lowest."

Write a query that returns title, author, price, and stock_quantity for all books where stock_quantity is greater than 0, ordered by price descending.

<details>
<summary>Show Solution</summary>

```sql
SELECT title, author, price, stock_quantity
FROM bookstore.books
WHERE stock_quantity > 0
ORDER BY price DESC;
```

**What this does:**
- `SELECT` lists the columns you want to see
- `FROM bookstore.books` specifies the table (with the schema prefix)
- `WHERE stock_quantity > 0` filters out books with zero stock
- `ORDER BY price DESC` sorts results from highest to lowest price

</details>

---

## Exercise 2: Filtering with Multiple Conditions (Easy)

**Business question:** "Which technical books cost less than $45?"

Write a query that returns the title, author, and price of books where the genre is 'Technical' and the price is below 45.00.

<details>
<summary>Show Solution</summary>

```sql
SELECT title, author, price
FROM bookstore.books
WHERE genre = 'Technical'
  AND price < 45.00
ORDER BY price;
```

**What this does:**
- `AND` combines two conditions - both must be true for a row to appear in the results
- String comparisons in PostgreSQL use single quotes: `'Technical'`
- `ORDER BY price` without DESC defaults to ascending (lowest first)

</details>

---

## Exercise 3: Aggregate Functions (Easy)

**Business question:** "How many books do we carry, what is our average price, and what is the total value of our inventory?"

Write a query that returns:
- Total number of books (count of rows)
- Average book price (rounded to 2 decimal places)
- Total inventory value (sum of price times stock_quantity for all books)

<details>
<summary>Show Solution</summary>

```sql
SELECT
    COUNT(*)                                AS total_books,
    ROUND(AVG(price), 2)                    AS avg_price,
    SUM(price * stock_quantity)             AS total_inventory_value
FROM bookstore.books;
```

**What this does:**
- `COUNT(*)` counts all rows in the table
- `AVG(price)` calculates the average of the price column
- `ROUND(..., 2)` rounds to 2 decimal places
- `SUM(price * stock_quantity)` multiplies price by quantity for each row, then sums the results
- `AS` gives each computed column a readable name (alias)

</details>

---

## Exercise 4: GROUP BY (Moderate)

**Business question:** "How many customers do we have in each state, and which state has the most?"

Write a query that shows each state with the count of customers, ordered by count descending.

<details>
<summary>Show Solution</summary>

```sql
SELECT state, COUNT(*) AS customer_count
FROM bookstore.customers
GROUP BY state
ORDER BY customer_count DESC;
```

**What this does:**
- `GROUP BY state` groups all rows with the same state value together
- `COUNT(*)` then counts how many rows are in each group
- `ORDER BY customer_count DESC` puts the state with the most customers first
- You can use the alias `customer_count` in the ORDER BY clause

</details>

---

## Exercise 5: Simple JOIN (Moderate)

**Business question:** "Show me all orders with the customer's name. I need the order ID, customer first and last name, order date, and status."

Write a query that joins the orders table with the customers table.

<details>
<summary>Show Solution</summary>

```sql
SELECT
    o.order_id,
    c.first_name,
    c.last_name,
    o.order_date,
    o.status
FROM bookstore.orders o
JOIN bookstore.customers c ON o.customer_id = c.customer_id
ORDER BY o.order_date DESC;
```

**What this does:**
- `JOIN` (also called INNER JOIN) combines rows from two tables based on a matching condition
- `ON o.customer_id = c.customer_id` is the join condition - it matches each order to its customer
- `o` and `c` are table aliases, which are short names you give to each table so you do not have to write the full name every time
- The result includes only orders that have a matching customer (INNER JOIN excludes orphan rows)

</details>

---

## Exercise 6: Multi-Table JOIN (Moderate)

**Business question:** "For each order, show me which books were ordered and the quantity of each. Include the customer name, book title, quantity, and unit price."

Write a query that joins orders, order_items, customers, and books.

<details>
<summary>Show Solution</summary>

```sql
SELECT
    o.order_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    b.title                             AS book_title,
    oi.quantity,
    oi.unit_price
FROM bookstore.orders o
JOIN bookstore.customers c   ON o.customer_id = c.customer_id
JOIN bookstore.order_items oi ON o.order_id   = oi.order_id
JOIN bookstore.books b       ON oi.book_id    = b.book_id
ORDER BY o.order_id, b.title;
```

**What this does:**
- Three JOINs chain together: orders -> customers, orders -> order_items -> books
- `||` is PostgreSQL's string concatenation operator. `first_name || ' ' || last_name` produces "Alice Johnson"
- Each JOIN adds more detail to the result set
- The order of JOINs does not affect the result - PostgreSQL's query optimizer decides the actual execution order

</details>

---

## Exercise 7: Subqueries (Moderate)

**Business question:** "Which customers have never placed an order?"

Write a query that finds customers who do not appear in the orders table.

<details>
<summary>Show Solution</summary>

```sql
SELECT first_name, last_name, email
FROM bookstore.customers
WHERE customer_id NOT IN (
    SELECT DISTINCT customer_id
    FROM bookstore.orders
);
```

**What this does:**
- The inner query (`SELECT DISTINCT customer_id FROM orders`) builds a list of all customer IDs that have placed at least one order
- `NOT IN (...)` filters the outer query to only include customers whose ID is not in that list
- `DISTINCT` removes duplicate customer IDs from the inner query (a customer with 3 orders would appear 3 times without it)

**Alternative approach using LEFT JOIN:**

```sql
SELECT c.first_name, c.last_name, c.email
FROM bookstore.customers c
LEFT JOIN bookstore.orders o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;
```

The LEFT JOIN version is often faster on large tables because NOT IN can have performance issues with large subquery results. Both produce the same result.

</details>

---

## Exercise 8: GROUP BY with HAVING (Moderate)

**Business question:** "Which customers have placed more than one order? Show their name and order count."

Write a query that groups orders by customer and filters to only those with more than one order.

<details>
<summary>Show Solution</summary>

```sql
SELECT
    c.first_name,
    c.last_name,
    COUNT(o.order_id) AS order_count
FROM bookstore.customers c
JOIN bookstore.orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(o.order_id) > 1
ORDER BY order_count DESC;
```

**What this does:**
- `GROUP BY c.customer_id, c.first_name, c.last_name` groups all orders by customer
- `COUNT(o.order_id)` counts how many orders each customer has
- `HAVING COUNT(o.order_id) > 1` filters groups after aggregation. `WHERE` filters rows before grouping; `HAVING` filters groups after grouping
- `c.customer_id` is included in GROUP BY even though it is not in SELECT - this is valid and ensures the grouping is correct (two people could have the same name)

</details>

---

## Exercise 9: Revenue Analysis with JOINs and Aggregates (Challenging)

**Business question:** "What is the total revenue per genre? Which genre is most profitable? Only count completed orders."

Write a query that calculates total revenue per book genre from completed orders only.

<details>
<summary>Show Solution</summary>

```sql
SELECT
    b.genre,
    COUNT(DISTINCT o.order_id)         AS total_orders,
    SUM(oi.quantity)                   AS total_books_sold,
    SUM(oi.quantity * oi.unit_price)   AS total_revenue
FROM bookstore.order_items oi
JOIN bookstore.orders o ON oi.order_id = o.order_id
JOIN bookstore.books b  ON oi.book_id  = b.book_id
WHERE o.status = 'completed'
GROUP BY b.genre
ORDER BY total_revenue DESC;
```

**What this does:**
- Three tables joined: order_items (the line items), orders (for the status filter), and books (for the genre)
- `WHERE o.status = 'completed'` filters to only completed orders before any grouping happens
- `COUNT(DISTINCT o.order_id)` counts unique orders per genre (one order can have items from multiple genres)
- `SUM(oi.quantity * oi.unit_price)` calculates revenue from the line item level - using the price recorded at the time of purchase, not the current book price
- `GROUP BY b.genre` produces one row per genre

</details>

---

## Exercise 10: Top Customers Report (Challenging)

**Business question:** "Build a customer report showing: customer name, total orders, total amount spent, their most recent order date, and their average order value. Sort by total spent, descending. Only include customers who have placed at least one order."

<details>
<summary>Show Solution</summary>

```sql
SELECT
    c.first_name || ' ' || c.last_name  AS customer_name,
    COUNT(o.order_id)                    AS total_orders,
    SUM(o.total_amount)                  AS total_spent,
    MAX(o.order_date)                    AS last_order_date,
    ROUND(AVG(o.total_amount), 2)        AS avg_order_value
FROM bookstore.customers c
JOIN bookstore.orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_spent DESC;
```

**What this does:**
- `COUNT(o.order_id)` - number of orders per customer
- `SUM(o.total_amount)` - total money spent across all orders
- `MAX(o.order_date)` - most recent order date (MAX on a date gives the latest)
- `AVG(o.total_amount)` - average order value
- `ROUND(..., 2)` - keeps the average to 2 decimal places
- The JOIN naturally excludes customers with no orders (INNER JOIN only returns matches), which satisfies the "at least one order" requirement without needing a HAVING clause

</details>

---

## Cleanup

When you are done with the exercises, you can remove the schema and all its objects:

```sql
DROP SCHEMA bookstore CASCADE;
```

The `CASCADE` keyword drops all objects (tables, sequences) inside the schema. Only run this when you are finished practicing.

---

## Summary of Key Takeaways

- `WHERE` filters individual rows before grouping. `HAVING` filters groups after aggregation. They are not interchangeable.
- `JOIN` (INNER JOIN) returns only matching rows. `LEFT JOIN` returns all rows from the left table even if there is no match on the right.
- Always use table aliases (`o`, `c`, `b`) when joining multiple tables. It makes queries readable and avoids ambiguous column errors.
- `GROUP BY` must include every non-aggregated column in the SELECT list. If you SELECT `first_name`, it must be in GROUP BY.
- Use `COUNT(DISTINCT ...)` when you need to count unique values within a group - not just total rows.
- Revenue calculations should use the price recorded in the order_items table (what the customer actually paid), not the current price in the books table (which may have changed).
- These SQL skills apply identically to Aurora PostgreSQL and standard RDS PostgreSQL. The engine is PostgreSQL in both cases.
