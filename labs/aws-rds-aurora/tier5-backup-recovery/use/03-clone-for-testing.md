# USE 03 - Clone for Testing
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 30 minutes
**Format:** Guided hands-on exercise with an Aurora PostgreSQL cluster
**Goal:** Clone a production-like Aurora cluster, run a schema migration on the clone, validate it, and prove the source was not affected.

**Prerequisites:**
- An Aurora PostgreSQL cluster with data (from BUILD 03 or your own)
- AWS CLI configured with rds permissions

---

## Scenario

You are the DBA for [COMPANY]. The engineering team wants to add a new column to the `products` table and create two new indexes. They are worried about:

1. How long the ALTER TABLE will lock the table
2. Whether the new indexes will cause table bloat
3. Whether any existing queries will slow down

Your job: clone production, run the migration on the clone, measure the impact, and report back before they touch production.

---

## Step 1 - Set Variables

```bash
export SOURCE_CLUSTER="suta-t5-aurora-hfa"
export CLONE_CLUSTER="suta-t5-clone-testing-hfa"
export CLONE_INSTANCE="suta-t5-clone-testing-inst"
export AWS_REGION="us-east-1"
export DB_SUBNET_GROUP="your-subnet-group"
export VPC_SG_ID="sg-xxxxxxxxxxxxxxxxx"
```

---

## Step 2 - Baseline the Source Cluster

Before cloning, record the current state of the source cluster.

Get the source endpoint:

```bash
export SOURCE_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $SOURCE_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)
```

Record the baseline metrics:

```bash
psql -h $SOURCE_HOST -U postgres -d postgres << 'EOF'
-- Row counts
SELECT schemaname, tablename, n_live_tup AS live_rows
FROM pg_stat_user_tables
ORDER BY tablename;

-- Table sizes
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size('public.'||tablename)) AS data_size,
    pg_size_pretty(pg_indexes_size('public.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size('public.'||tablename) DESC;

-- Existing indexes
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
EOF
```

Write down these numbers. You will compare clone results against them.

---

## Step 3 - Create the Fast Clone

```bash
aws rds restore-db-cluster-to-point-in-time \
  --db-cluster-identifier $CLONE_CLUSTER \
  --source-db-cluster-identifier $SOURCE_CLUSTER \
  --restore-type copy-on-write \
  --use-latest-restorable-time \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --region $AWS_REGION
```

Add a DB instance to the clone:

```bash
aws rds create-db-instance \
  --db-instance-identifier $CLONE_INSTANCE \
  --db-cluster-identifier $CLONE_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION
```

Wait for both to be ready:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier $CLONE_CLUSTER \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $CLONE_INSTANCE \
  --region $AWS_REGION
```

Get the clone endpoint:

```bash
export CLONE_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLONE_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)
```

---

## Step 4 - Verify the Clone Has Production Data

```bash
psql -h $CLONE_HOST -U postgres -d postgres \
  -c "SELECT COUNT(*) FROM products;"
```

This must return the same count as the source. If the counts differ, the clone did not capture the latest state. Check the `--use-latest-restorable-time` flag and retry.

---

## Step 5 - Run the Migration on the Clone

The engineering team's migration plan:

```sql
-- Migration 001: add discount column
ALTER TABLE products ADD COLUMN discount_rate NUMERIC(5,4) DEFAULT 0.00;

-- Migration 002: backfill discount rates for Gold tier customers
UPDATE products SET discount_rate = 0.15 WHERE category = 'Electronics';
UPDATE products SET discount_rate = 0.10 WHERE category = 'Clothing';

-- Migration 003: add search index
CREATE INDEX CONCURRENTLY idx_products_category_price
    ON products(category, price DESC);

-- Migration 004: add partial index for high-value items
CREATE INDEX CONCURRENTLY idx_products_expensive
    ON products(price DESC)
    WHERE price > 750;
```

Connect to the clone and run the migration:

```bash
psql -h $CLONE_HOST -U postgres -d postgres
```

Start a timer before each ALTER/UPDATE/CREATE INDEX:

```sql
\timing on
```

`\timing on` prints execution time after each command in psql.

Run each migration step separately and record the time:

```sql
ALTER TABLE products ADD COLUMN discount_rate NUMERIC(5,4) DEFAULT 0.00;
```

Expected output (yours will differ):

```
ALTER TABLE
Time: 1823.456 ms
```

Record: `ALTER TABLE ADD COLUMN: 1.8 seconds`

```sql
UPDATE products SET discount_rate = 0.15 WHERE category = 'Electronics';
```

Expected output (yours will differ):

```
UPDATE 2471
Time: 340.123 ms
```

```sql
UPDATE products SET discount_rate = 0.10 WHERE category = 'Clothing';
```

```sql
CREATE INDEX CONCURRENTLY idx_products_category_price
    ON products(category, price DESC);
```

> **Concept:** `CREATE INDEX CONCURRENTLY` builds the index without locking the table for writes. It takes longer but does not block production traffic. Always use `CONCURRENTLY` in production.

```sql
CREATE INDEX CONCURRENTLY idx_products_expensive
    ON products(price DESC)
    WHERE price > 750;
```

Record all timing results. Exit:

```sql
\q
```

---

## Step 6 - Measure Migration Impact

After the migration, compare the before and after state on the clone:

```bash
psql -h $CLONE_HOST -U postgres -d postgres << 'EOF'
-- Check table sizes after migration
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size('public.'||tablename)) AS data_size,
    pg_size_pretty(pg_indexes_size('public.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size('public.'||tablename) DESC;

-- Verify new indexes exist
SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'products'
ORDER BY indexname;

-- Verify the new column
SELECT
    COUNT(*) AS total_rows,
    COUNT(discount_rate) AS rows_with_discount,
    AVG(discount_rate)::NUMERIC(5,4) AS avg_discount
FROM products;
EOF
```

Expected output (yours will differ):

```
 tablename | total_size | data_size | index_size
-----------+------------+-----------+------------
 products  | 4512 kB    | 2048 kB   | 2464 kB

                indexname                | index_size
-----------------------------------------+------------
 idx_products_category_price             | 312 kB
 idx_products_expensive                  | 88 kB
 products_pkey                           | 240 kB

 total_rows | rows_with_discount | avg_discount
------------+--------------------+--------------
      10000 |              10000 |       0.0494
```

---

## Step 7 - Test Query Performance on Clone

Run the queries the application uses most. Compare explain plans before and after.

Before the new indexes:

```bash
psql -h $CLONE_HOST -U postgres -d postgres << 'EOF'
-- Simulate the application's category search query
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT name, price, discount_rate
FROM products
WHERE category = 'Electronics'
ORDER BY price DESC
LIMIT 20;
EOF
```

Expected output (yours will differ, showing index scan):

```
 Limit  (cost=0.29..48.31 rows=20 width=...) (actual time=0.083..0.412 rows=20 loops=1)
   ->  Index Scan using idx_products_category_price on products  (cost=... rows=...) ...
         Index Cond: ((category = 'Electronics'::text))
 Planning Time: 0.234 ms
 Execution Time: 0.447 ms
```

The query now uses `idx_products_category_price`. Record the execution time.

---

## Step 8 - Verify Source Was Not Modified

Critical check: the source cluster must be unchanged.

```bash
psql -h $SOURCE_HOST -U postgres -d postgres << 'EOF'
-- This column must NOT exist on the source
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'products' AND column_name = 'discount_rate';
EOF
```

Expected output:

```
 column_name
-------------
(0 rows)
```

The column does not exist on the source. The migration is completely isolated to the clone.

---

## Step 9 - Write the Migration Report

Fill out this report template and send it to the engineering team:

```
SCHEMA MIGRATION PRE-FLIGHT REPORT
====================================
Date: [DATE]
Tested by: [YOUR NAME]
Source cluster: [CLUSTER NAME]
Clone cluster: [CLONE NAME]
Clone created at: [TIMESTAMP]

MIGRATION STEPS AND TIMING
---------------------------
Step 1 - ALTER TABLE ADD COLUMN: [TIME] ms
Step 2 - UPDATE Electronics discount: [TIME] ms, [ROWS] rows affected
Step 3 - UPDATE Clothing discount: [TIME] ms, [ROWS] rows affected
Step 4 - CREATE INDEX CONCURRENTLY (category, price): [TIME] ms
Step 5 - CREATE INDEX CONCURRENTLY (price partial): [TIME] ms

Total estimated migration time: [SUM] ms

STORAGE IMPACT
--------------
Table size before: [SIZE]
Table size after: [SIZE]
Index size added: [SIZE]
Total storage increase: [SIZE]

QUERY PERFORMANCE IMPACT
------------------------
Electronics category search before: [TIME] ms (seq scan / index scan)
Electronics category search after: [TIME] ms (index scan)
Performance change: [+/-]%

RISKS IDENTIFIED
----------------
[ ] No locks expected on writes during migration (CONCURRENTLY used)
[ ] ALTER TABLE ADD COLUMN with default is instant in PostgreSQL 11+
[ ] Backfill UPDATE will hold row locks (monitor for long-running transactions)

RECOMMENDATION
--------------
[ ] Safe to apply to production during low-traffic window
[ ] Recommend scheduling during [TIME WINDOW]
[ ] Monitor with: SELECT * FROM pg_stat_activity WHERE query LIKE '%UPDATE products%';
```

---

## Step 10 - Cleanup

Delete the clone instance first:

```bash
aws rds delete-db-instance \
  --db-instance-identifier $CLONE_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds wait db-instance-deleted \
  --db-instance-identifier $CLONE_INSTANCE \
  --region $AWS_REGION
```

Delete the clone cluster:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier $CLONE_CLUSTER \
  --skip-final-snapshot \
  --region $AWS_REGION
```

---

## Key Takeaways

- A fast clone gave you a full copy of production data in minutes instead of hours
- You measured exact migration timing without any risk to production
- You confirmed query performance improved with the new indexes
- You have a written report with real numbers to share with the team
- The source cluster was untouched throughout

This workflow should be standard practice for any schema change that runs longer than 1 second in testing.
