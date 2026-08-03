# USE 03 - Vector Search: Semantic Product Search

**Time:** 30 minutes
**Level:** Intermediate
**Prerequisite:** BUILD 04 completed

---

## Scenario

[COMPANY] wants to add "find similar products" to their e-commerce site. Traditional keyword search misses products with different words but similar meaning. For example, a search for "running shoes" should also return "athletic footwear" and "jogging sneakers."

Your job is to build the semantic search backend using pgvector on RDS PostgreSQL.

**Note:** In production you would use OpenAI or a similar service to generate embeddings. In this lab you will use pre-computed embeddings to simulate the AI model output. The SQL patterns are exactly the same.

---

## Part 1 - Set Up the Schema

**Connect to your database:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d [DBNAME]
```

**Ensure pgvector is installed:**

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

**Create the products table:**

```sql
CREATE TABLE ecom_products (
  id           serial PRIMARY KEY,
  name         text NOT NULL,
  description  text,
  category     text,
  price        numeric(10,2),
  embedding    vector(8),  -- 8 dimensions (simplified; real: 1536)
  created_at   timestamptz DEFAULT now()
);
```

---

## Part 2 - Load Sample Data

The embeddings below are hand-crafted to cluster similar items together. The first 4 dimensions represent "footwear-ness" and the last 4 represent "outdoor-ness." This is a simplification of how real embeddings work.

```sql
INSERT INTO ecom_products (name, description, category, price, embedding) VALUES
  -- Athletic footwear cluster
  ('Running Shoes Pro',
   'High-performance running shoes for serious athletes',
   'footwear', 89.99,
   '[0.91, 0.87, 0.12, 0.08, 0.72, 0.68, 0.15, 0.11]'),

  ('Athletic Sneakers',
   'Versatile athletic footwear for gym and casual wear',
   'footwear', 64.99,
   '[0.88, 0.84, 0.14, 0.10, 0.58, 0.52, 0.22, 0.18]'),

  ('Jogging Trainers',
   'Lightweight trainers designed for jogging and running',
   'footwear', 74.99,
   '[0.90, 0.85, 0.13, 0.09, 0.75, 0.70, 0.12, 0.10]'),

  ('Sport Walking Shoes',
   'Comfortable shoes for brisk walking and light exercise',
   'footwear', 54.99,
   '[0.82, 0.78, 0.18, 0.14, 0.50, 0.45, 0.28, 0.22]'),

  -- Outdoor gear cluster
  ('Hiking Boots Expedition',
   'Heavy-duty boots for challenging mountain terrain',
   'outdoor', 149.99,
   '[0.15, 0.12, 0.88, 0.85, 0.91, 0.87, 0.09, 0.07]'),

  ('Trail Runners',
   'Off-road running shoes for trail and mountain paths',
   'outdoor', 109.99,
   '[0.72, 0.68, 0.55, 0.50, 0.88, 0.84, 0.13, 0.10]'),

  ('Waterproof Hiking Shoes',
   'Waterproof footwear for wet trails and river crossings',
   'outdoor', 129.99,
   '[0.18, 0.15, 0.85, 0.82, 0.89, 0.85, 0.11, 0.09]'),

  -- Electronics cluster (should NOT appear in footwear searches)
  ('Wireless Earbuds Sport',
   'Sweat-resistant earbuds for active use',
   'electronics', 79.99,
   '[0.08, 0.06, 0.07, 0.09, 0.12, 0.10, 0.91, 0.88]'),

  ('Fitness Tracker Watch',
   'GPS smartwatch for tracking runs and workouts',
   'electronics', 199.99,
   '[0.05, 0.08, 0.06, 0.07, 0.55, 0.52, 0.88, 0.85]'),

  ('Heart Rate Monitor',
   'Chest strap heart rate monitor for serious athletes',
   'electronics', 49.99,
   '[0.04, 0.06, 0.05, 0.07, 0.48, 0.45, 0.85, 0.82]');
```

**Verify the data:**

```sql
SELECT id, name, category, price
FROM ecom_products
ORDER BY id;
```

Expected output (yours will differ):
```
 id |          name           |  category   | price
----+-------------------------+-------------+--------
  1 | Running Shoes Pro       | footwear    |  89.99
  2 | Athletic Sneakers       | footwear    |  64.99
  ...
(10 rows)
```

---

## Part 3 - Run Exact (No Index) Similarity Search

Without an index, PostgreSQL scans all rows. This is called an exact nearest neighbor search - 100% accurate but slow at scale.

**Simulate a user searching for "running shoes":**

The query embedding below represents "running shoes" - high footwear dimensions, moderate outdoor dimensions:

```sql
SELECT
  id,
  name,
  category,
  price,
  round((embedding <=> '[0.90, 0.86, 0.13, 0.09, 0.73, 0.69, 0.13, 0.10]')::numeric, 4) AS cosine_dist
FROM ecom_products
ORDER BY cosine_dist ASC
LIMIT 5;
```

Expected output (yours will differ):
```
 id |         name          |  category   | price  | cosine_dist
----+-----------------------+-------------+--------+-------------
  1 | Running Shoes Pro     | footwear    |  89.99 |      0.0001
  3 | Jogging Trainers      | footwear    |  74.99 |      0.0003
  2 | Athletic Sneakers     | footwear    |  64.99 |      0.0015
  6 | Trail Runners         | outdoor     | 109.99 |      0.0082
  4 | Sport Walking Shoes   | footwear    |  54.99 |      0.0094
(5 rows)
```

The search correctly finds footwear items. The electronics cluster appears much further away.

**Check if the query used an index:**

```sql
EXPLAIN SELECT *
FROM ecom_products
ORDER BY embedding <=> '[0.90, 0.86, 0.13, 0.09, 0.73, 0.69, 0.13, 0.10]'
LIMIT 5;
```

Look for `Seq Scan` - confirming no index was used.

---

## Part 4 - Create an HNSW Index for Production

For production use with many rows and concurrent queries, create an HNSW index.

```sql
CREATE INDEX ecom_products_embedding_cosine_idx
ON ecom_products
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);
```

**Set the query parameter for higher accuracy:**

```sql
SET hnsw.ef_search = 40;
```

**Run the same search again:**

```sql
SELECT
  id,
  name,
  category,
  price,
  round((embedding <=> '[0.90, 0.86, 0.13, 0.09, 0.73, 0.69, 0.13, 0.10]')::numeric, 4) AS cosine_dist
FROM ecom_products
ORDER BY cosine_dist ASC
LIMIT 5;
```

**Verify the index is being used:**

```sql
EXPLAIN SELECT *
FROM ecom_products
ORDER BY embedding <=> '[0.90, 0.86, 0.13, 0.09, 0.73, 0.69, 0.13, 0.10]'
LIMIT 5;
```

Look for `Index Scan using ecom_products_embedding_cosine_idx` in the plan.

---

## Part 5 - Add Filtering to the Search

A real product search also needs filtering - by category, price range, or availability.

**Search only within "footwear" category:**

```sql
SELECT
  id,
  name,
  category,
  price,
  round((embedding <=> '[0.90, 0.86, 0.13, 0.09, 0.73, 0.69, 0.13, 0.10]')::numeric, 4) AS cosine_dist
FROM ecom_products
WHERE category = 'footwear'
ORDER BY cosine_dist ASC
LIMIT 3;
```

**Search within a price range:**

```sql
SELECT
  id,
  name,
  price,
  round((embedding <=> '[0.90, 0.86, 0.13, 0.09, 0.73, 0.69, 0.13, 0.10]')::numeric, 4) AS cosine_dist
FROM ecom_products
WHERE price BETWEEN 50 AND 100
ORDER BY cosine_dist ASC
LIMIT 5;
```

> **Note:** When you add a WHERE clause, PostgreSQL may fall back to a sequential scan (because the index alone can't filter rows efficiently). This is expected. For high-performance filtered vector search, consider a partial index or a hybrid search approach.

---

## Part 6 - Find Similar Products (Item-to-Item)

Given a product the user is viewing, find similar products. This uses the stored embedding of the current product.

```sql
-- User is viewing "Running Shoes Pro" (id=1)
-- Find 4 most similar products (excluding the current product)
WITH current_product AS (
  SELECT embedding
  FROM ecom_products
  WHERE id = 1
)
SELECT
  e.id,
  e.name,
  e.category,
  e.price,
  round((e.embedding <=> cp.embedding)::numeric, 4) AS similarity_score
FROM ecom_products e, current_product cp
WHERE e.id != 1
ORDER BY similarity_score ASC
LIMIT 4;
```

Expected output (yours will differ):
```
 id |        name         |  category   | price  | similarity_score
----+---------------------+-------------+--------+------------------
  3 | Jogging Trainers    | footwear    |  74.99 |           0.0002
  2 | Athletic Sneakers   | footwear    |  64.99 |           0.0016
  6 | Trail Runners       | outdoor     | 109.99 |           0.0080
  4 | Sport Walking Shoes | footwear    |  54.99 |           0.0098
(4 rows)
```

---

## Part 7 - Build a Search Function

Package the search into a reusable function:

```sql
CREATE OR REPLACE FUNCTION search_products(
  query_embedding vector(8),
  result_limit    integer DEFAULT 5,
  min_price       numeric DEFAULT 0,
  max_price       numeric DEFAULT 9999
)
RETURNS TABLE (
  product_id   integer,
  product_name text,
  category     text,
  price        numeric,
  similarity   numeric
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    id,
    name,
    category,
    price,
    round((embedding <=> query_embedding)::numeric, 4)
  FROM ecom_products
  WHERE price BETWEEN min_price AND max_price
  ORDER BY embedding <=> query_embedding
  LIMIT result_limit;
$$;
```

**Use the function:**

```sql
-- Search for running shoes under $100
SELECT *
FROM search_products(
  '[0.90, 0.86, 0.13, 0.09, 0.73, 0.69, 0.13, 0.10]',
  5,         -- limit
  0,         -- min price
  100        -- max price
);
```

---

## Discussion Questions

1. You have 10 million product vectors. HNSW index build is taking 3 hours. What options do you have?

2. A user searches for "waterproof shoes." The vector search returns sandals. What might be wrong?

3. What is the difference between `<->` (L2) and `<=>` (cosine) distance? When would you choose each?

4. Your vector search accuracy is poor (wrong products returned). What HNSW parameter would you increase?

5. The product team wants to search by both semantic similarity AND a keyword match in the name field. How would you implement a hybrid search?

---

## Cleanup

```sql
DROP FUNCTION IF EXISTS search_products(vector(8), integer, numeric, numeric);
DROP TABLE IF EXISTS ecom_products;
```
