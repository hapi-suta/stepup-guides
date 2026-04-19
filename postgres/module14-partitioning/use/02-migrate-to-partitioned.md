# Exercise 02: Migrate the orders Table to a Partitioned Table

**Duration:** 30 minutes
**Objective:** Move all data from the existing non-partitioned `orders` table into `orders_partitioned` with zero data loss. Verify row counts before and after.

**Prerequisites:**
- `orders_partitioned` exists with monthly partitions (from Guide 01/02)
- `orders` table has data from the Pulse worker

---

## Background

You rarely get to start with a partitioned table in production. More often, you inherit a large unpartitioned table and must migrate it. The challenge is doing this without losing data and without extended downtime. The approach here is:

1. Record the exact row count before migration
2. Bulk-load data from `orders` into `orders_partitioned`
3. Verify the row count matches exactly
4. Verify no rows landed in the default partition unexpectedly

This is NOT a zero-downtime migration (the application still writes to `orders` while you migrate). A true zero-downtime migration requires logical replication or application-level dual-writes. For this exercise, you learn the data movement mechanics.

---

## Step 1: Record Pre-Migration Row Count

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Record the exact row count from the source table. Save this number - you will compare it after migration:

```sql
SELECT COUNT(*) AS source_row_count FROM orders;
```

Expected output (yours will differ):

```
 source_row_count
------------------
          1482300
(1 row)
```

Also record the date range so you know which partitions need to exist:

```sql
SELECT MIN(order_date) AS earliest, MAX(order_date) AS latest FROM orders;
```

Expected output (yours will differ):

```
  earliest  |   latest
------------+------------
 2023-01-01 | 2025-03-31
(1 row)
```

Your `orders_partitioned` table currently has partitions from 2024-01 through 2025-06. You are missing 2023. Check what exists:

```sql
SELECT child.relname, pg_get_expr(child.relpartbound, child.oid) AS bounds
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_partitioned'
ORDER BY child.relname;
```

Expected output (yours will differ):

```
  partition_name   |                      bounds
-------------------+----------------------------------------------
 orders_2024_01    | FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')
 ...
 orders_2025_06    | FOR VALUES FROM ('2025-06-01') TO ('2025-07-01')
 orders_default    | DEFAULT
(18 rows)
```

---

## Step 2: Create Missing 2023 Partitions

You need partitions for all 12 months of 2023. The `orders_default` partition will catch them if they are missing, but rows in the default partition do not benefit from pruning.

Create all 2023 monthly partitions:

```sql
CREATE TABLE orders_2023_01 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-01-01') TO ('2023-02-01');
```

```sql
CREATE TABLE orders_2023_02 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-02-01') TO ('2023-03-01');
```

```sql
CREATE TABLE orders_2023_03 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-03-01') TO ('2023-04-01');
```

```sql
CREATE TABLE orders_2023_04 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-04-01') TO ('2023-05-01');
```

```sql
CREATE TABLE orders_2023_05 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-05-01') TO ('2023-06-01');
```

```sql
CREATE TABLE orders_2023_06 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-06-01') TO ('2023-07-01');
```

```sql
CREATE TABLE orders_2023_07 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-07-01') TO ('2023-08-01');
```

```sql
CREATE TABLE orders_2023_08 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-08-01') TO ('2023-09-01');
```

```sql
CREATE TABLE orders_2023_09 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-09-01') TO ('2023-10-01');
```

```sql
CREATE TABLE orders_2023_10 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-10-01') TO ('2023-11-01');
```

```sql
CREATE TABLE orders_2023_11 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-11-01') TO ('2023-12-01');
```

```sql
CREATE TABLE orders_2023_12 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-12-01') TO ('2024-01-01');
```

Verify the 2023 partitions were created:

```sql
SELECT COUNT(*) AS partition_count
FROM pg_inherits
WHERE inhparent = 'orders_partitioned'::regclass;
```

Expected output (yours will differ):

```
 partition_count
-----------------
              30
(1 row)
```

---

## Step 3: Load Data Into the Partitioned Table

Clear any existing data in `orders_partitioned` first (from Guide 01 test rows):

```sql
TRUNCATE orders_partitioned;
```

Expected output:

```
TRUNCATE TABLE
```

Now bulk-load all data from `orders` into `orders_partitioned`. PostgreSQL will route each row to the correct partition based on `order_date`:

```sql
INSERT INTO orders_partitioned
SELECT
    order_id,
    customer_id,
    order_date,
    status,
    total_amount,
    region
FROM orders;
```

Expected output (yours will differ - this may take 30-60 seconds):

```
INSERT 0 1482300
```

The number after `INSERT 0` is the row count inserted. It should match your source count from Step 1.

---

## Step 4: Verify Zero Data Loss

Count rows in the partitioned table:

```sql
SELECT COUNT(*) AS partitioned_row_count FROM orders_partitioned;
```

Expected output (yours will differ):

```
 partitioned_row_count
-----------------------
               1482300
(1 row)
```

Compare counts - this query should return 0 if all rows were migrated:

```sql
SELECT
    (SELECT COUNT(*) FROM orders) AS source,
    (SELECT COUNT(*) FROM orders_partitioned) AS partitioned,
    (SELECT COUNT(*) FROM orders) - (SELECT COUNT(*) FROM orders_partitioned) AS difference;
```

Expected output:

```
  source  | partitioned | difference
----------+-------------+------------
  1482300 |     1482300 |          0
(1 row)
```

Check that the default partition is empty (all rows should have landed in proper monthly partitions):

```sql
SELECT COUNT(*) AS rows_in_default FROM orders_default;
```

Expected output:

```
 rows_in_default
-----------------
               0
(1 row)
```

If the default partition has rows, check which dates they have - those are dates with no matching partition:

```sql
SELECT order_date, COUNT(*) AS cnt
FROM orders_default
GROUP BY order_date
ORDER BY order_date;
```

If this returns rows, you need to create partitions for those dates and then re-insert those rows.

---

## Step 5: Verify Per-Partition Data Distribution

Check that rows are distributed across partitions as expected:

```sql
SELECT
    child.relname AS partition_name,
    COUNT(*) AS row_count
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
JOIN orders_partitioned op ON op.tableoid = child.oid
WHERE parent.relname = 'orders_partitioned'
GROUP BY child.relname
ORDER BY child.relname;
```

Expected output (yours will differ):

```
  partition_name  | row_count
------------------+-----------
 orders_2023_01   |     38741
 orders_2023_02   |     35290
 ...
 orders_2025_03   |     43901
(27 rows)
```

Verify the date range in a specific partition matches its bounds:

```sql
SELECT MIN(order_date), MAX(order_date)
FROM orders_2024_06;
```

Expected output (yours will differ):

```
    min     |    max
------------+------------
 2024-06-01 | 2024-06-30
(1 row)
```

---

## Step 6: Run ANALYZE

After a large bulk load, run ANALYZE so the query planner has accurate statistics:

```sql
ANALYZE orders_partitioned;
```

Expected output:

```
ANALYZE
```

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## Checkpoint

- [ ] You captured the source row count before migration and confirmed it matched after
- [ ] You created all necessary partitions before loading data (so zero rows went to the default partition)
- [ ] You used a bulk `INSERT INTO ... SELECT` to migrate all rows in one operation
- [ ] You verified the default partition is empty after migration
- [ ] You checked per-partition row counts to confirm data is in the correct partitions
- [ ] You ran ANALYZE after the bulk load
