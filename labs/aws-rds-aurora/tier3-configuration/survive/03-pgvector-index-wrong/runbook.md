# SURVIVE 03 - pgvector Index Wrong Configuration

**Difficulty:** Intermediate-Advanced
**Estimated time:** 25 minutes

---

## The Situation

The product search feature is returning wrong results. Users are reporting:

- "I searched for laptops and got results for running shoes"
- "The same search returns different products every time"
- "Search worked for a week and then got worse after more products were added"

The search function is `search_catalog()`. It uses pgvector for semantic search.

---

## What You Know

- The pgvector extension is installed
- An index exists on the embedding column
- Results are inconsistent and often wrong
- There is no obvious SQL error - the query runs but returns bad data

---

## Your Goal

- Diagnose why search results are inaccurate
- Fix the index configuration and query parameters
- Verify search results are accurate after the fix

---

## Step 1 - Understand the Current Setup

**Connect to the database:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d [DBNAME]
```

**Check the current index on the embeddings table:**

```sql
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'vector_products';
```

Expected output:
```
          indexname          |                         indexdef
-----------------------------+----------------------------------------------------------
 vector_products_pkey        | CREATE UNIQUE INDEX vector_products_pkey ON ...
 vector_products_bad_idx     | CREATE INDEX vector_products_bad_idx ON vector_products
                             | USING ivfflat (embedding vector_cosine_ops) WITH (lists=5)
(2 rows)
```

**Check the table row count:**

```sql
SELECT COUNT(*) FROM vector_products;
```

**Look at the `lists` parameter in the IVFFlat index:**

```sql
SELECT
  indexname,
  reloptions
FROM pg_class c
JOIN pg_index i ON c.oid = i.indexrelid
WHERE c.relname = 'vector_products_bad_idx';
```

**Check the search function source:**

```sql
SELECT prosrc
FROM pg_proc
WHERE proname = 'search_catalog';
```

Look for `SET LOCAL ivfflat.probes`. This tells you how many lists are being searched at query time.

---

## Step 2 - Diagnose the Problems

There are two problems with this setup. You need to find both.

### Problem A - Too Few Lists

For an IVFFlat index, the recommended number of `lists` is `sqrt(row_count)`.

```sql
-- Calculate recommended lists value
SELECT
  COUNT(*) AS row_count,
  round(sqrt(COUNT(*))::numeric, 0) AS recommended_lists,
  5 AS current_lists
FROM vector_products;
```

Expected output:
```
 row_count | recommended_lists | current_lists
-----------+-------------------+---------------
     50000 |               224 |             5
(1 row)
```

With only 5 lists for 50,000 rows, each list has ~10,000 vectors. The index is nearly useless - it barely narrows down the search space.

### Problem B - Probes Too Low

Examine the search function:

```sql
SELECT prosrc FROM pg_proc WHERE proname = 'search_catalog';
```

You will see `SET LOCAL ivfflat.probes = 1`. With only 1 probe and 5 total lists, the search looks at only 1/5 of the index. This is extremely low recall.

**Test the recall problem:**

```sql
-- Run a search and record the results
SELECT id, name, distance
FROM search_catalog('[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5]'::vector, 5);
```

Run this same query 5 times. Compare results. You will see different products returned each time - a sign of poor recall.

**Verify by comparing index search vs exact search:**

```sql
-- Exact search (no index - ground truth)
SET enable_indexscan = off;
SELECT id, name,
  round((embedding <=> '[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5]'::vector)::numeric, 6) AS exact_dist
FROM vector_products
ORDER BY exact_dist
LIMIT 5;

-- Index search (current broken config)
RESET enable_indexscan;
SET ivfflat.probes = 1;
SELECT id, name,
  round((embedding <=> '[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5]'::vector)::numeric, 6) AS approx_dist
FROM vector_products
ORDER BY approx_dist
LIMIT 5;
```

Compare the two result sets. The IDs should overlap significantly for a good index. A broken index returns almost no matches in common.

---

## Step 3 - Fix the Index

### Option A - Rebuild with Correct Lists (Recommended)

Drop the bad index and create a new one with the correct `lists` value:

```sql
-- Drop the bad index
DROP INDEX vector_products_bad_idx;
```

```sql
-- Create with correct lists (sqrt of 50000 = ~224)
CREATE INDEX vector_products_embedding_idx
ON vector_products
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 224);
```

Index build on 50,000 rows takes about 30-60 seconds.

### Option B - Switch to HNSW (Better Long-Term)

For high-recall production workloads, HNSW is usually the better choice:

```sql
-- Drop the IVFFlat index
DROP INDEX vector_products_bad_idx;
```

```sql
-- Create HNSW index instead
CREATE INDEX vector_products_hnsw_idx
ON vector_products
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);
```

HNSW build on 50,000 rows takes 2-5 minutes. Better query speed and recall than IVFFlat.

---

## Step 4 - Fix the Search Function

After fixing the index, fix the `probes` setting in the search function.

**For IVFFlat (if you chose Option A):**

```sql
CREATE OR REPLACE FUNCTION search_catalog(
  query_vec vector(16),
  result_count integer DEFAULT 10
)
RETURNS TABLE(id integer, name text, category text, distance numeric)
LANGUAGE plpgsql
AS $$
BEGIN
  -- probes should be sqrt(lists) as a minimum
  -- For 224 lists, use at least 15 probes
  SET LOCAL ivfflat.probes = 15;

  RETURN QUERY
  SELECT
    vp.id,
    vp.name,
    vp.category,
    round((vp.embedding <=> query_vec)::numeric, 6) AS distance
  FROM vector_products vp
  ORDER BY vp.embedding <=> query_vec
  LIMIT result_count;
END;
$$;
```

**For HNSW (if you chose Option B):**

```sql
CREATE OR REPLACE FUNCTION search_catalog(
  query_vec vector(16),
  result_count integer DEFAULT 10
)
RETURNS TABLE(id integer, name text, category text, distance numeric)
LANGUAGE plpgsql
AS $$
BEGIN
  -- ef_search controls recall for HNSW
  -- 40 is the default; increase for higher recall
  SET LOCAL hnsw.ef_search = 40;

  RETURN QUERY
  SELECT
    vp.id,
    vp.name,
    vp.category,
    round((vp.embedding <=> query_vec)::numeric, 6) AS distance
  FROM vector_products vp
  ORDER BY vp.embedding <=> query_vec
  LIMIT result_count;
END;
$$;
```

---

## Step 5 - Verify the Fix

**Run the recall comparison test again:**

```sql
-- Exact search (ground truth)
SET enable_indexscan = off;
SELECT id FROM vector_products
ORDER BY embedding <=> '[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5]'::vector
LIMIT 10;
```

```sql
-- Index search (should now match)
RESET enable_indexscan;
SELECT id FROM vector_products
ORDER BY embedding <=> '[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5]'::vector
LIMIT 10;
```

The top results should now overlap significantly (8-10 out of 10 matching).

**Test that the search function is consistent:**

Run `search_catalog(...)` 5 times with the same input. The results should be the same or nearly identical every time.

---

## Root Cause and Prevention

**Root cause 1:** IVFFlat index created with `lists = 5` for a 50,000-row table. The recommended value is `sqrt(row_count)` = 224. Too few lists means each list is huge, so the index provides almost no search space reduction.

**Root cause 2:** `probes = 1` means only 1 list is searched at query time. Even with a good number of lists, searching only 1 is not enough. The recommendation is `probes = sqrt(lists)`.

**Prevention:**

1. **Use the recommended formulas:**
   - `lists` = `sqrt(row_count)` (round to nearest integer)
   - `probes` = `sqrt(lists)` as a minimum starting point

2. **Test recall before going to production.** Compare exact scan results vs index scan results for your data.

3. **Monitor as data grows.** IVFFlat's `lists` value is fixed at build time. As row count grows, rebuild the index with a new `lists` value periodically.

4. **Consider HNSW for production.** HNSW adjusts better to varying data sizes and provides more consistent recall.

5. **Track recall metrics.** Build a test suite that compares approximate search results to exact results and alerts if recall drops below 90%.

---

## Run validate.sh to confirm your fix is complete.
