# Module 14 - Table Partitioning
## Guide 02: Managing Partitions

**Objective:** Learn to add new partitions, use a default partition for unmatched rows, attach and detach partitions from a live table, and drop old partitions as part of a data archival workflow.

**Time:** 30-35 minutes

**Prerequisites:**
- Completed Guide 01 (`orders_partitioned` table exists with 15 monthly partitions)
- PostgreSQL 16 running on port 5432
- `stepup_store` database

---

## 1. Add a Default Partition

A default partition catches rows that do not match any existing partition bound. Without a default partition, inserting a row with an out-of-range date raises an error.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Try inserting a row with a date beyond your current partitions (April 2025):

```sql
INSERT INTO orders_partitioned (order_id, customer_id, order_date, status, total_amount, region)
VALUES (8888888, 2, '2025-04-10', 'pending', 150.00, 'West');
```

Expected output:

```
ERROR:  no partition of relation "orders_partitioned" found for row
DETAIL:  Partition key of the failing row contains (order_date) = (2025-04-10).
```

The insert failed because there is no partition for April 2025. Now create a default partition to catch all future unmatched rows:

```sql
CREATE TABLE orders_default
    PARTITION OF orders_partitioned
    DEFAULT;
```

Expected output:

```
CREATE TABLE
```

Retry the insert:

```sql
INSERT INTO orders_partitioned (order_id, customer_id, order_date, status, total_amount, region)
VALUES (8888888, 2, '2025-04-10', 'pending', 150.00, 'West');
```

Expected output:

```
INSERT 0 1
```

Verify it landed in the default partition:

```sql
SELECT tableoid::regclass AS partition_name, order_id, order_date
FROM orders_partitioned
WHERE order_id = 8888888;
```

Expected output:

```
 partition_name | order_id | order_date
----------------+----------+------------
 orders_default |  8888888 | 2025-04-10
(1 row)
```

> **Concept - Default partition is a safety net, not a permanent home**
> The default partition prevents insert failures when new date ranges arrive before you add the next partition. However, rows sitting in the default partition do NOT benefit from pruning - a query for April 2025 data still has to scan the default partition, plus it cannot prune based on the default partition's "all other values" nature. Always monitor the default partition and move rows to proper partitions promptly. You will do this in the SURVIVE scenarios.

---

## 2. Add New Monthly Partitions

Add April 2025 as a proper partition. But first, check whether any rows in the default partition would fall in that range:

```sql
SELECT COUNT(*) FROM orders_default
WHERE order_date >= '2025-04-01' AND order_date < '2025-05-01';
```

Expected output (yours will differ):

```
 count
-------
     1
(1 row)
```

There is 1 row in the default partition that belongs in April 2025. You cannot create the April partition while that row exists in default - PostgreSQL will refuse the creation because the new partition's bounds would overlap with rows already in the default partition.

Move that row out of the default partition by deleting it temporarily (you will re-insert after creating the partition):

```sql
DELETE FROM orders_default
WHERE order_date >= '2025-04-01' AND order_date < '2025-05-01'
RETURNING *;
```

Expected output (yours will differ):

```
 order_id | customer_id | order_date | status  | total_amount | region
----------+-------------+------------+---------+--------------+--------
  8888888 |           2 | 2025-04-10 | pending |       150.00 | West
(1 row)
```

Now create the April 2025 partition:

```sql
CREATE TABLE orders_2025_04
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
```

Expected output:

```
CREATE TABLE
```

Re-insert the row - it will now route to the correct partition:

```sql
INSERT INTO orders_partitioned (order_id, customer_id, order_date, status, total_amount, region)
VALUES (8888888, 2, '2025-04-10', 'pending', 150.00, 'West');
```

Expected output:

```
INSERT 0 1
```

Verify:

```sql
SELECT tableoid::regclass AS partition_name, order_id, order_date
FROM orders_partitioned
WHERE order_id = 8888888;
```

Expected output:

```
  partition_name  | order_id | order_date
------------------+----------+------------
 orders_2025_04   |  8888888 | 2025-04-10
(1 row)
```

Add May and June 2025 to stay ahead of the data:

```sql
CREATE TABLE orders_2025_05
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
```

```sql
CREATE TABLE orders_2025_06
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
```

Clean up the test row:

```sql
DELETE FROM orders_partitioned WHERE order_id = 8888888;
```

---

## 3. Detach a Partition

Detaching a partition removes it from the partitioned table but keeps it as a standalone table. This is the first step in archival: detach the old partition, archive it, then drop it.

First, check what data is in the January 2024 partition before detaching:

```sql
SELECT COUNT(*), MIN(order_date), MAX(order_date)
FROM orders_2024_01;
```

Expected output (yours will differ):

```
 count | min        | max
-------+------------+------------
     0 | (null)     | (null)
(1 row)
```

The partition is empty because you have not migrated the original orders data yet (that is Guide 03's exercise). For now you are learning the mechanics of DETACH.

Detach the January 2024 partition using `DETACH PARTITION CONCURRENTLY`. The `CONCURRENTLY` option uses a weaker lock that does not block reads or writes on the parent table - critical for production use:

```sql
ALTER TABLE orders_partitioned
    DETACH PARTITION orders_2024_01 CONCURRENTLY;
```

Expected output:

```
ALTER TABLE
```

> **Concept - DETACH CONCURRENTLY vs plain DETACH**
> Plain `DETACH PARTITION` takes an `ACCESS EXCLUSIVE` lock on the parent table, blocking all reads and writes for the duration of the operation. On a large, busy table this can cause a queue of waiting queries. `DETACH PARTITION CONCURRENTLY` (added in PG14) uses a weaker lock that allows reads and writes to continue. It takes longer to complete but is production-safe. Always use `CONCURRENTLY` in production unless you are in a maintenance window.

Verify the partition is now a standalone table (no longer listed under orders_partitioned):

```sql
SELECT child.relname
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_partitioned'
AND child.relname = 'orders_2024_01';
```

Expected output:

```
 relname
---------
(0 rows)
```

But the table still exists as a standalone table:

```sql
\dt orders_2024_01
```

Expected output:

```
           List of relations
 Schema |      Name      | Type  |  Owner
--------+----------------+-------+----------
 public | orders_2024_01 | table | postgres
(1 row)
```

---

## 4. Attach an Existing Table as a Partition

You can go the other direction too: take an existing plain table and attach it as a partition. This is useful for loading historical data or for bulk-loading a month's data into a plain table first (faster, no overhead), then attaching it.

The `orders_2024_01` table is now a plain table. Reattach it to the partitioned table. PostgreSQL will scan the table to verify all rows satisfy the partition bounds before completing the attach:

```sql
ALTER TABLE orders_partitioned
    ATTACH PARTITION orders_2024_01
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

Expected output:

```
ALTER TABLE
```

Verify it is back:

```sql
SELECT child.relname, pg_get_expr(child.relpartbound, child.oid) AS bounds
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_partitioned'
AND child.relname = 'orders_2024_01';
```

Expected output:

```
   relname    |                   bounds
--------------+----------------------------------------------
 orders_2024_01 | FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')
(1 row)
```

> **Concept - ATTACH scans the table**
> When you `ATTACH PARTITION`, PostgreSQL validates that every row in the existing table satisfies the new partition bounds. On a large table this can take a long time and holds a lock. To speed this up, add a CHECK constraint to the table BEFORE attaching it - PostgreSQL trusts the constraint and skips the full scan. Example: `ALTER TABLE orders_2024_01 ADD CONSTRAINT chk_date CHECK (order_date >= '2024-01-01' AND order_date < '2024-02-01') NOT VALID;` followed by `VALIDATE CONSTRAINT chk_date;`. The validate step happens with a lighter lock than the ATTACH scan.

---

## 5. Drop an Old Partition (Data Archival)

Dropping a partition permanently deletes all rows in that partition. This is instant because PostgreSQL just drops the child table - no per-row processing needed.

First, confirm the partition you are about to drop is empty (you never loaded data into it):

```sql
SELECT COUNT(*) FROM orders_2024_01;
```

Expected output:

```
 count
-------
     0
(1 row)
```

Drop the partition:

```sql
DROP TABLE orders_2024_01;
```

Expected output:

```
DROP TABLE
```

Verify it is gone from both the partitioned table and the database:

```sql
SELECT COUNT(*) FROM pg_class WHERE relname = 'orders_2024_01';
```

Expected output:

```
 count
-------
     0
(1 row)
```

> **Concept - DROP TABLE vs DETACH + DROP**
> Dropping a partition directly (`DROP TABLE orders_2024_01`) removes the table and all its data instantly. If you want to archive the data first (export to CSV, move to cold storage), you must DETACH the partition first (making it a standalone table), archive the data, then DROP the standalone table. You practice this full workflow in USE Exercise 04.

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

You have completed Guide 02. Verify you understand the following:

- [ ] You can explain what a default partition does and why it is a safety net, not a permanent home
- [ ] You can create a default partition with `PARTITION OF ... DEFAULT`
- [ ] You understand why you must clear conflicting rows from the default partition before creating a new bounded partition
- [ ] You can add new partitions with `CREATE TABLE ... PARTITION OF ... FOR VALUES FROM ... TO`
- [ ] You know the difference between `DETACH PARTITION` and `DETACH PARTITION CONCURRENTLY` and when to use each
- [ ] You can attach an existing table as a partition with `ALTER TABLE ... ATTACH PARTITION`
- [ ] You understand that ATTACH scans the table for constraint validation, and how a pre-existing CHECK constraint speeds this up
- [ ] You can drop a partition with `DROP TABLE` and understand this permanently deletes the data

---

Proceed to **Guide 03 - Partition Indexes**
