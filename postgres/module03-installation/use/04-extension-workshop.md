# Exercise 04 - Extension Workshop

**Time estimate:** 30-35 minutes
**Prerequisites:** BUILD phase complete - CentOS Stream 9 with PostgreSQL 16 (RPM) running on port 5432. PGDATA at `/opt/pgsql/data`. Database `labdb` exists with extensions installed: pg_stat_statements, pgcrypto, pg_trgm, pageinspect.

---

## Scenario

A developer wants to add full-text search with fuzzy matching to their application. They also need to hash user passwords, generate UUIDs for API keys, and understand query performance. You will use the extensions you installed in the BUILD phase to solve real problems.

---

## Step 1 - Fuzzy Text Search with pg_trgm

Switch to the postgres user:

```bash
sudo -iu postgres
```

Connect to labdb:

```bash
psql -d labdb
```

Create a table of product names to search against:

```sql
CREATE TABLE catalog (
    id serial PRIMARY KEY,
    product_name text NOT NULL,
    category text,
    price numeric(8,2)
);
```

**Expected:**

```
CREATE TABLE
```

Insert sample data:

```sql
INSERT INTO catalog (product_name, category, price) VALUES
    ('PostgreSQL Administration Cookbook', 'Books', 49.99),
    ('PostgreSQL High Availability', 'Books', 44.95),
    ('Mastering PostgreSQL 16', 'Books', 39.99),
    ('MySQL Performance Tuning', 'Books', 34.99),
    ('MongoDB in Action', 'Books', 42.50),
    ('Redis Essentials', 'Books', 29.99),
    ('PostgreSQL 16 Server Side Programming', 'Books', 54.95),
    ('Database Reliability Engineering', 'Books', 47.00),
    ('Postgres Vacuum Handbook', 'Books', 19.99),
    ('Learning SQL for Beginners', 'Books', 24.99);
```

**Expected:**

```
INSERT 0 10
```

Use the `similarity()` function to find products similar to a misspelled search term. The function returns a value between 0 (no match) and 1 (exact match):

```sql
SELECT product_name, similarity(product_name, 'Postgre Administration')
FROM catalog
ORDER BY similarity(product_name, 'Postgre Administration') DESC
LIMIT 5;
```

**Expected:**

```
              product_name               | similarity
-----------------------------------------+------------
 PostgreSQL Administration Cookbook       |   0.489796
 PostgreSQL High Availability            |   0.222222
 Mastering PostgreSQL 16                 |       0.16
 ...
```

The top result matches despite the typo ("Postgre" instead of "PostgreSQL"). The similarity score tells you how close the match is.

Now use the `%` operator (the trigram similarity operator) in a WHERE clause with a threshold. First, check the current similarity threshold:

```sql
SHOW pg_trgm.similarity_threshold;
```

**Expected:**

```
 pg_trgm.similarity_threshold
-------------------------------
 0.3
(1 row)
```

The default threshold is 0.3. Any similarity score at or above this value will match. Lower it to catch more fuzzy matches:

```sql
SET pg_trgm.similarity_threshold = 0.15;
```

**Expected:**

```
SET
```

Search for products matching a misspelled term using the `%` operator:

```sql
SELECT product_name, similarity(product_name, 'Postgrss') AS score
FROM catalog
WHERE product_name % 'Postgrss'
ORDER BY score DESC;
```

**Expected:**

```
              product_name               |  score
-----------------------------------------+----------
 PostgreSQL Administration Cookbook       | 0.176471
 PostgreSQL High Availability            | 0.176471
 Mastering PostgreSQL 16                 | 0.166667
 PostgreSQL 16 Server Side Programming   |     0.16
 Postgres Vacuum Handbook                | 0.153846
```

The `%` operator found all PostgreSQL-related products despite the typo "Postgrss".

> **Concept: Trigram Matching for Search**
> Trigrams break strings into overlapping 3-character sequences. "cat" becomes {"  c", " ca", "cat", "at "}. Two strings that share many trigrams are considered similar. This is fundamentally different from `LIKE` - which requires exact substring matches - because trigrams tolerate typos, transposed characters, and missing letters. This is how many search applications implement "did you mean?" suggestions.

Create a GIN index to speed up trigram searches. Without this index, PostgreSQL scans every row and computes similarity for each one:

```sql
CREATE INDEX idx_catalog_trgm ON catalog USING gin (product_name gin_trgm_ops);
```

**Expected:**

```
CREATE INDEX
```

Verify the index is used. On a small table the planner might choose a sequential scan, but the index is ready for when the table grows:

```sql
EXPLAIN SELECT * FROM catalog WHERE product_name % 'PostgreSQL';
```

**Expected (may vary based on table size):**

```
                                    QUERY PLAN
----------------------------------------------------------------------------------
 Bitmap Heap Scan on catalog  (cost=...)
   Recheck Cond: (product_name % 'PostgreSQL'::text)
   ->  Bitmap Index Scan on idx_catalog_trgm  (cost=...)
         Index Cond: (product_name % 'PostgreSQL'::text)
```

Reset the similarity threshold:

```sql
RESET pg_trgm.similarity_threshold;
```

**Expected:**

```
RESET
```

---

## Step 2 - Password Hashing and UUIDs with pgcrypto

The developer needs to store hashed passwords and generate API keys. Use `pgcrypto` for both.

Create a users table:

```sql
CREATE TABLE app_users (
    user_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    username text UNIQUE NOT NULL,
    password_hash text NOT NULL,
    api_key uuid DEFAULT gen_random_uuid(),
    created_at timestamptz DEFAULT now()
);
```

**Expected:**

```
CREATE TABLE
```

Insert a user with a hashed password. The `crypt()` function hashes the password, and `gen_salt('bf')` generates a bcrypt salt. Bcrypt is the industry standard for password hashing because it is intentionally slow - making brute-force attacks impractical:

```sql
INSERT INTO app_users (username, password_hash)
VALUES ('alice', crypt('s3cur3P@ss', gen_salt('bf')));
```

**Expected:**

```
INSERT 0 1
```

View the stored record:

```sql
SELECT user_id, username, password_hash, api_key FROM app_users;
```

**Expected (your UUIDs and hash will differ):**

```
               user_id                | username |                        password_hash                         |               api_key
--------------------------------------+----------+--------------------------------------------------------------+--------------------------------------
 a3b7c9d1-4e5f-6a7b-8c9d-0e1f2a3b4c5d | alice    | $2a$06$xR7k... (60-character bcrypt hash)                    | f1e2d3c4-b5a6-7890-abcd-ef1234567890
```

Notice that `user_id` and `api_key` were automatically generated as UUIDs by the `gen_random_uuid()` default.

Verify a password against the stored hash. The `crypt()` function re-hashes the input with the same salt embedded in the stored hash:

```sql
SELECT username,
       (password_hash = crypt('s3cur3P@ss', password_hash)) AS password_correct
FROM app_users
WHERE username = 'alice';
```

**Expected:**

```
 username | password_correct
----------+------------------
 alice    | t
```

Test with a wrong password:

```sql
SELECT username,
       (password_hash = crypt('wrongpassword', password_hash)) AS password_correct
FROM app_users
WHERE username = 'alice';
```

**Expected:**

```
 username | password_correct
----------+------------------
 alice    | f
```

> **Concept: Never Store Plaintext Passwords**
> Bcrypt hashing with `crypt()` and `gen_salt('bf')` is the correct way to store passwords in a database. The salt is embedded in the hash output, so you do not need to store it separately. Each call to `gen_salt('bf')` produces a different salt, which means the same password produces a different hash every time - preventing rainbow table attacks. The `'bf'` parameter selects the Blowfish (bcrypt) algorithm with a default cost factor of 6 iterations.

Generate a SHA-256 hash of arbitrary data. This is useful for checksums or content-addressable storage:

```sql
SELECT encode(digest('important document content', 'sha256'), 'hex') AS content_hash;
```

**Expected:**

```
                            content_hash
------------------------------------------------------------------
 (64-character hex string)
```

---

## Step 3 - Find Slow Queries with pg_stat_statements

The developer reports that "the app feels slow" and wants to know which queries are the bottleneck. `pg_stat_statements` has been collecting data since you enabled it in the BUILD phase.

Run a few queries to generate some statistics:

```sql
SELECT count(*) FROM catalog WHERE product_name LIKE '%SQL%';
```

```sql
SELECT * FROM app_users WHERE username = 'alice';
```

```sql
SELECT category, avg(price) FROM catalog GROUP BY category;
```

Now query `pg_stat_statements` to find the top queries by total execution time:

```sql
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    rows
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'labdb')
ORDER BY total_exec_time DESC
LIMIT 10;
```

**Expected (your values will differ):**

```
                        query_preview                         | calls | total_ms | avg_ms | rows
--------------------------------------------------------------+-------+----------+--------+------
 CREATE INDEX idx_catalog_trgm ON catalog USING gin (product_ |     1 |    15.23 |  15.23 |    0
 SELECT product_name, similarity(product_name, $1) FROM catal |     1 |     2.14 |   2.14 |    5
 INSERT INTO catalog (product_name, category, price) VALUES ( |     1 |     1.87 |   1.87 |   10
 ...
```

The `calls` column shows how many times each query ran. The `total_exec_time` is the cumulative execution time across all calls. The `mean_exec_time` is the average per call.

To find the most frequently called queries (which might indicate missing caching):

```sql
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    rows,
    round(mean_exec_time::numeric, 4) AS avg_ms
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'labdb')
ORDER BY calls DESC
LIMIT 5;
```

**Expected:** The queries you have run most often appear at the top.

> **Concept: Tuning Starts with Measurement**
> `pg_stat_statements` is the starting point for all query optimization work. Without it, you are guessing which queries are slow. The typical workflow is: (1) find queries with the highest `total_exec_time`, (2) run `EXPLAIN ANALYZE` on them, (3) add indexes or rewrite the query, (4) reset stats with `pg_stat_statements_reset()` and monitor again. In production, this extension should be enabled on every server.

---

## Step 4 - Examine Physical Page Layout with pageinspect

The developer is curious about how PostgreSQL stores data internally. Use `pageinspect` to look at the raw storage.

Check the page header of the catalog table's first page. Page 0 is the first 8KB block of the table:

```sql
SELECT * FROM page_header(get_raw_page('catalog', 0));
```

**Expected:**

```
    lsn    | checksum | flags | lower | upper | special | pagesize | version | prune_xid
-----------+----------+-------+-------+-------+---------+----------+---------+-----------
 0/XXXXXXX |        0 |     0 |    68 |  7xxx |    8192 |     8192 |       4 |         0
```

The `lower` value tells you where the line pointer array ends. The `upper` value tells you where the actual tuple data starts. Free space is `upper - lower` bytes.

Calculate the free space and the fill percentage:

```sql
SELECT
    lower,
    upper,
    upper - lower AS free_space_bytes,
    round(100.0 * (upper - lower) / pagesize, 1) AS free_pct
FROM page_header(get_raw_page('catalog', 0));
```

**Expected:**

```
 lower | upper | free_space_bytes | free_pct
-------+-------+------------------+----------
    68 |  7xxx |             xxxx |     xx.x
```

Now look at individual tuples on the page:

```sql
SELECT
    lp AS line_pointer,
    lp_off AS offset,
    lp_len AS length,
    t_xmin AS created_by_txn,
    t_xmax AS deleted_by_txn,
    t_ctid AS current_location
FROM heap_page_items(get_raw_page('catalog', 0));
```

**Expected:**

```
 line_pointer | offset | length | created_by_txn | deleted_by_txn | current_location
--------------+--------+--------+----------------+----------------+------------------
            1 |   8xxx |     xx |            xxx |              0 | (0,1)
            2 |   8xxx |     xx |            xxx |              0 | (0,2)
            3 |   8xxx |     xx |            xxx |              0 | (0,3)
 ...
```

All `deleted_by_txn` values are 0, meaning every row is live (not deleted). The `current_location` column shows `(page, item)` - when it points to itself, the tuple is the current version.

Now update a row and observe MVCC in action:

```sql
UPDATE catalog SET price = 59.99 WHERE id = 1;
```

**Expected:**

```
UPDATE 1
```

Check the page again:

```sql
SELECT
    lp AS line_pointer,
    lp_off AS offset,
    lp_len AS length,
    t_xmin AS created_by_txn,
    t_xmax AS deleted_by_txn,
    t_ctid AS current_location
FROM heap_page_items(get_raw_page('catalog', 0));
```

**Expected:** You should see that line pointer 1 now has a non-zero `deleted_by_txn` value, and its `current_location` points to a new tuple (e.g., `(0,11)`). The new tuple (line pointer 11) has `deleted_by_txn = 0` and points to itself. This is MVCC - the old version is marked as deleted but not yet removed (VACUUM handles that).

> **Concept: MVCC Visible in Storage**
> `pageinspect` lets you see what `SELECT` hides. When you UPDATE a row, PostgreSQL does not modify the original tuple. It marks the old tuple with the updating transaction's ID (`t_xmax`) and writes a brand new tuple. Both versions exist on the page simultaneously. Active transactions that started before the UPDATE still see the old version. This is Multi-Version Concurrency Control. VACUUM later removes the old version once no transaction can see it.

---

## Step 5 - Clean Up

Drop the tables you created:

```sql
DROP TABLE catalog;
```

**Expected:**

```
DROP TABLE
```

```sql
DROP TABLE app_users;
```

**Expected:**

```
DROP TABLE
```

Exit psql:

```sql
\q
```

Exit the postgres user:

```bash
exit
```

---

## Checkpoint

Before moving on, confirm you can:

- [ ] Use `similarity()` and the `%` operator for fuzzy text search
- [ ] Create a GIN trigram index with `gin_trgm_ops` and explain why it helps `LIKE '%pattern%'` queries
- [ ] Hash passwords with `crypt()` and `gen_salt('bf')` and verify them
- [ ] Generate UUIDs with `gen_random_uuid()` for primary keys and API tokens
- [ ] Query `pg_stat_statements` to find the slowest and most frequent queries
- [ ] Use `page_header()` and `heap_page_items()` to examine a table's physical layout
- [ ] Explain how UPDATE creates a new tuple version (MVCC) visible through `pageinspect`

---

**Next:** Exercise 05 - Installation Troubleshooting
