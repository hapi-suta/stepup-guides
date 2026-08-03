# USE 02 - Slow Query Investigation

**Time:** 60 minutes
**Difficulty:** Advanced
**Prerequisites:** Build 02, 04, 05 complete. pg_stat_statements enabled with track_io_timing=on.

---

## Objective

Given a database with 5 intentionally problematic query patterns, use Performance Insights and pg_stat_statements to identify, diagnose, and fix each one. Verify each fix reduces query time by at least 50%.

---

## Setup - Inject Slow Queries

Connect to your database and create the test schema:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders_v2 CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    country TEXT NOT NULL,
    premium BOOLEAN DEFAULT FALSE
);

CREATE TABLE products (
    product_id BIGSERIAL PRIMARY KEY,
    sku TEXT UNIQUE NOT NULL,
    category TEXT NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    in_stock BOOLEAN DEFAULT TRUE
);

CREATE TABLE orders_v2 (
    order_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    total NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE order_items (
    item_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(10,2) NOT NULL
);
```

Load data:

```sql
INSERT INTO users (username, email, country, premium)
SELECT 'user_' || g, 'user_' || g || '@example.com',
    CASE (g % 5) WHEN 0 THEN 'US' WHEN 1 THEN 'UK' WHEN 2 THEN 'DE' WHEN 3 THEN 'FR' ELSE 'CA' END,
    (random() > 0.8)
FROM generate_series(1, 200000) g;

INSERT INTO products (sku, category, price, in_stock)
SELECT 'SKU-' || lpad(g::TEXT, 6, '0'),
    CASE (g % 8) WHEN 0 THEN 'Electronics' WHEN 1 THEN 'Clothing' WHEN 2 THEN 'Books'
        WHEN 3 THEN 'Home' WHEN 4 THEN 'Sports' WHEN 5 THEN 'Food'
        WHEN 6 THEN 'Beauty' ELSE 'Toys' END,
    (random() * 500 + 1)::NUMERIC(10,2),
    (random() > 0.1)
FROM generate_series(1, 50000) g;

INSERT INTO orders_v2 (user_id, status, total, created_at)
SELECT (random() * 200000 + 1)::BIGINT,
    CASE (random() * 4)::INT WHEN 0 THEN 'pending' WHEN 1 THEN 'processing'
        WHEN 2 THEN 'shipped' ELSE 'delivered' END,
    (random() * 1000 + 10)::NUMERIC(12,2),
    now() - (random() * interval '365 days')
FROM generate_series(1, 2000000);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT (random() * 2000000 + 1)::BIGINT, (random() * 50000 + 1)::BIGINT,
    (random() * 5 + 1)::INT, (random() * 500 + 1)::NUMERIC(10,2)
FROM generate_series(1, 5000000);

ANALYZE users, products, orders_v2, order_items;
SELECT pg_stat_statements_reset();
```

Now run the 5 slow query patterns to accumulate statistics:

```sql
-- Pattern 1: No index on status (full table scan)
DO $$ BEGIN FOR i IN 1..30 LOOP
    PERFORM count(*) FROM orders_v2 WHERE status = 'pending' AND total > 100;
END LOOP; END $$;

-- Pattern 2: Large sort spilling to disk
SET work_mem = '4MB';
DO $$ BEGIN FOR i IN 1..10 LOOP
    PERFORM user_id, sum(total) FROM orders_v2 GROUP BY user_id ORDER BY sum(total) DESC LIMIT 100;
END LOOP; END $$;
RESET work_mem;

-- Pattern 3: N+1 pattern
DO $$ DECLARE v_uid BIGINT; BEGIN
    FOR v_uid IN SELECT user_id FROM users LIMIT 500 LOOP
        PERFORM count(*) FROM orders_v2 WHERE user_id = v_uid;
    END LOOP;
END $$;

-- Pattern 4: No join index
DO $$ BEGIN FOR i IN 1..5 LOOP
    PERFORM o.order_id, count(oi.item_id), sum(oi.unit_price * oi.quantity)
    FROM orders_v2 o JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.created_at > now() - interval '30 days'
    GROUP BY o.order_id ORDER BY sum(oi.unit_price * oi.quantity) DESC LIMIT 1000;
END LOOP; END $$;

-- Pattern 5: Leading wildcard LIKE
DO $$ BEGIN FOR i IN 1..20 LOOP
    PERFORM product_id, sku, price FROM products WHERE sku LIKE '%000' AND in_stock = TRUE;
END LOOP; END $$;
```

---

## Task 1 - Find the Top 5 Slow Queries

```sql
SELECT queryid, left(query, 100) AS query_snippet, calls,
    round(total_exec_time::numeric / 1000, 1) AS total_seconds,
    round(mean_exec_time::numeric, 1) AS avg_ms,
    round((total_exec_time / sum(total_exec_time) OVER ()) * 100, 1) AS pct_of_total,
    temp_blks_written, shared_blks_read
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%' AND query NOT LIKE '%DO $$%'
ORDER BY total_exec_time DESC LIMIT 10;
```

Write down the top 5 queries and their avg_ms before fixing anything.

---

## Task 2 - Diagnose and Fix Each Query

For each query, follow this process:

**Step A:** Get the execution plan with `EXPLAIN (ANALYZE, BUFFERS)`.
**Step B:** Identify the problem (Seq Scan, external merge Disk, etc.).
**Step C:** Apply the fix and verify improvement.

<details>
<summary>Fix 1 - Add index on orders_v2.status</summary>

```sql
CREATE INDEX CONCURRENTLY idx_orders_v2_status_total
ON orders_v2(status, total) WHERE status IN ('pending', 'processing');
```
</details>

<details>
<summary>Fix 2 - Increase work_mem for sort-heavy queries</summary>

```sql
SET work_mem = '64MB';
-- Re-run the query and confirm Sort Method changes from "external merge Disk" to "quicksort Memory"
```
</details>

<details>
<summary>Fix 3 - Rewrite N+1 as a single JOIN</summary>

```sql
SELECT u.user_id, count(o.order_id) AS order_count
FROM users u
LEFT JOIN orders_v2 o ON u.user_id = o.user_id
WHERE u.user_id IN (SELECT user_id FROM users LIMIT 500)
GROUP BY u.user_id;
```
</details>

<details>
<summary>Fix 4 - Add index on order_items.order_id</summary>

```sql
CREATE INDEX CONCURRENTLY idx_order_items_order_id ON order_items(order_id);
```
</details>

<details>
<summary>Fix 5 - Use pg_trgm for LIKE matching</summary>

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_products_sku_trgm ON products USING gin(sku gin_trgm_ops);
```
</details>

---

## Task 3 - Measure the Improvement

Reset stats, re-run queries, and compare:

```sql
SELECT pg_stat_statements_reset();
```

Re-run all 5 patterns with fixes applied, then check:

```sql
SELECT queryid, left(query, 100) AS query_snippet, calls,
    round(mean_exec_time::numeric, 1) AS avg_ms_after
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC LIMIT 10;
```

Fill out this table:

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
