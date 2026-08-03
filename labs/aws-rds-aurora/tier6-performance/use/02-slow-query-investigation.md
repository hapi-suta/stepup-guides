# USE 02 - Find and Fix the Top 5 Slow Queries

**Time:** 60 minutes
**Difficulty:** Advanced
**Prerequisites:** Build 02, 03, 05 complete. pg_stat_statements enabled with track_io_timing=on.

---

## Objective

Given a database with a set of pre-existing queries (some intentionally bad), use Performance Insights and pg_stat_statements to identify the top 5 queries by total execution time, diagnose each one, and implement a fix. Verify each fix reduces query time by at least 50%.

---

## Setup - Inject Slow Queries

Run this setup script to create tables and insert problematic queries into your workload:

```sql
-- Drop and recreate test schema
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders_v2 CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    country TEXT NOT NULL,
    signup_date DATE NOT NULL,
    premium BOOLEAN DEFAULT FALSE
);

CREATE TABLE products (
    product_id BIGSERIAL PRIMARY KEY,
    sku TEXT UNIQUE NOT NULL,
    category TEXT NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    weight_kg NUMERIC(6,3),
    in_stock BOOLEAN DEFAULT TRUE
);

CREATE TABLE orders_v2 (
    order_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    total NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    shipped_at TIMESTAMPTZ
);

CREATE TABLE order_items (
    item_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(10,2) NOT NULL
);

-- Load data
INSERT INTO users (username, email, country, signup_date, premium)
SELECT
    'user_' || g,
    'user_' || g || '@example.com',
    CASE (g % 5) WHEN 0 THEN 'US' WHEN 1 THEN 'UK' WHEN 2 THEN 'DE' WHEN 3 THEN 'FR' ELSE 'CA' END,
    CURRENT_DATE - (random() * 1000)::INT,
    (random() > 0.8)
FROM generate_series(1, 200000) g;

INSERT INTO products (sku, category, price, weight_kg, in_stock)
SELECT
    'SKU-' || lpad(g::TEXT, 6, '0'),
    CASE (g % 8) WHEN 0 THEN 'Electronics' WHEN 1 THEN 'Clothing' WHEN 2 THEN 'Books'
        WHEN 3 THEN 'Home' WHEN 4 THEN 'Sports' WHEN 5 THEN 'Food'
        WHEN 6 THEN 'Beauty' ELSE 'Toys' END,
    (random() * 500 + 1)::NUMERIC(10,2),
    (random() * 20)::NUMERIC(6,3),
    (random() > 0.1)
FROM generate_series(1, 50000) g;

INSERT INTO orders_v2 (user_id, status, total, created_at, shipped_at)
SELECT
    (random() * 200000 + 1)::BIGINT,
    CASE (random() * 4)::INT WHEN 0 THEN 'pending' WHEN 1 THEN 'processing' WHEN 2 THEN 'shipped' ELSE 'delivered' END,
    (random() * 1000 + 10)::NUMERIC(12,2),
    now() - (random() * interval '365 days'),
    CASE WHEN random() > 0.3 THEN now() - (random() * interval '300 days') ELSE NULL END
FROM generate_series(1, 2000000);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    (random() * 2000000 + 1)::BIGINT,
    (random() * 50000 + 1)::BIGINT,
    (random() * 5 + 1)::INT,
    (random() * 500 + 1)::NUMERIC(10,2)
FROM generate_series(1, 5000000);

ANALYZE users, products, orders_v2, order_items;

-- Reset stats so we start clean
SELECT pg_stat_statements_reset();
```

Now inject the five slow query patterns (run each 20+ times to accumulate statistics):

```sql
-- Slow Query 1: No index on status column, full table scan
-- Run this 30 times
DO $$
BEGIN
    FOR i IN 1..30 LOOP
        PERFORM count(*) FROM orders_v2 WHERE status = 'pending' AND total > 100;
    END LOOP;
END $$;

-- Slow Query 2: Large sort with no work_mem
SET work_mem = '4MB';
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        PERFORM user_id, sum(total) FROM orders_v2 GROUP BY user_id ORDER BY sum(total) DESC LIMIT 100;
    END LOOP;
END $$;
RESET work_mem;

-- Slow Query 3: N+1 query pattern (very common in ORMs)
-- Simulated: one query per user for their order count
DO $$
DECLARE
    v_user_id BIGINT;
BEGIN
    FOR v_user_id IN SELECT user_id FROM users LIMIT 500 LOOP
        PERFORM count(*) FROM orders_v2 WHERE user_id = v_user_id;
    END LOOP;
END $$;

-- Slow Query 4: Inefficient JOIN - no index on order_items.order_id
DO $$
BEGIN
    FOR i IN 1..5 LOOP
        PERFORM o.order_id, count(oi.item_id), sum(oi.unit_price * oi.quantity)
        FROM orders_v2 o
        JOIN order_items oi ON o.order_id = oi.order_id
        WHERE o.created_at > now() - interval '30 days'
        GROUP BY o.order_id
        ORDER BY sum(oi.unit_price * oi.quantity) DESC
        LIMIT 1000;
    END LOOP;
END $$;

-- Slow Query 5: LIKE with leading wildcard - cannot use index
DO $$
BEGIN
    FOR i IN 1..20 LOOP
        PERFORM product_id, sku, price FROM products WHERE sku LIKE '%000' AND in_stock = TRUE;
    END LOOP;
END $$;
```

---

## Task 1 - Find the Top 5 Slow Queries

Use pg_stat_statements to rank them:

```sql
SELECT
    queryid,
    left(query, 100) AS query_snippet,
    calls,
    round(total_exec_time::numeric / 1000, 1) AS total_seconds,
    round(mean_exec_time::numeric, 1) AS avg_ms,
    round((total_exec_time / sum(total_exec_time) OVER ()) * 100, 1) AS pct_of_total,
    temp_blks_written,
    shared_blks_read
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
  AND query NOT LIKE '%DO $$%'
ORDER BY total_exec_time DESC
LIMIT 10;
```

Write down the top 5 queries and their total_seconds before you fix anything.

---

## Task 2 - Diagnose and Fix Each Query

For each of the 5 queries identified, follow this process:

**Step A - Get the execution plan:**

```sql
EXPLAIN (ANALYZE, BUFFERS) /* paste the query here */;
```

**Step B - Identify the problem from the plan:**
- `Seq Scan` on a large table = missing index
- `Sort Method: external merge Disk: ...` = work_mem spill
- Many separate queries instead of one join = N+1
- `Bitmap Heap Scan` with high `Rows Removed by Filter` = poor selectivity

**Step C - Apply the fix and verify improvement.**

Fixes for the 5 injected queries:

**Fix 1 - Add index on orders_v2.status:**

```sql
CREATE INDEX CONCURRENTLY idx_orders_v2_status_total
ON orders_v2(status, total)
WHERE status IN ('pending', 'processing');
```

**Fix 2 - Increase work_mem (per session for heavy analytical queries):**

```sql
-- In parameter group, increase global default
-- Or per-session for the application connection that runs reports:
SET work_mem = '64MB';
```

**Fix 3 - Rewrite N+1 as a single JOIN:**

```sql
-- Instead of 500 individual queries:
SELECT u.user_id, count(o.order_id) AS order_count
FROM users u
LEFT JOIN orders_v2 o ON u.user_id = o.user_id
WHERE u.user_id IN (SELECT user_id FROM users LIMIT 500)
GROUP BY u.user_id;
```

**Fix 4 - Add index on order_items.order_id:**

```sql
CREATE INDEX CONCURRENTLY idx_order_items_order_id
ON order_items(order_id);
```

**Fix 5 - Rewrite leading-wildcard LIKE:**

```sql
-- Option A: Store the suffix separately and index it
ALTER TABLE products ADD COLUMN IF NOT EXISTS sku_suffix TEXT;
UPDATE products SET sku_suffix = right(sku, 3);
CREATE INDEX idx_products_sku_suffix ON products(sku_suffix) WHERE in_stock = TRUE;

-- Then query:
SELECT product_id, sku, price
FROM products
WHERE sku_suffix = '000' AND in_stock = TRUE;

-- Option B: Use pg_trgm for LIKE matching (requires extension)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_products_sku_trgm ON products USING gin(sku gin_trgm_ops);
```

---

## Task 3 - Measure the Improvement

After applying each fix, reset pg_stat_statements and run each query 20 times again:

```sql
SELECT pg_stat_statements_reset();
```

Then rerun the query patterns from the inject step, and compare:

```sql
SELECT
    queryid,
    left(query, 100) AS query_snippet,
    calls,
    round(mean_exec_time::numeric, 1) AS avg_ms_after
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 10;
```

Fill out this comparison table:

| Query | Before (avg_ms) | After (avg_ms) | Improvement |
|-------|----------------|----------------|-------------|
| 1 - status filter | ___ | ___ | ___% |
| 2 - sort spill | ___ | ___ | ___% |
| 3 - N+1 | ___ | ___ | ___% |
| 4 - join no index | ___ | ___ | ___% |
| 5 - leading LIKE | ___ | ___ | ___% |

Target: each query should improve by at least 50%.

---

## Cleanup

```sql
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders_v2 CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS users CASCADE;
SELECT pg_stat_statements_reset();
```
