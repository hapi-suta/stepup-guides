# Scenario 01 - Default Partition Full

**Severity:** HIGH
**Expected Recovery Time:** 10-15 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: The orders_chaos table was just deployed.
All inserts are going to the default partition.
Queries are doing full scans - partition pruning is broken.
Fix the partition bounds and redistribute the data.
```

---

## Key Concepts for Revision

- **Default partition is a catch-all** - When a row does not match any bounded partition, it goes to the default partition. This happens silently - no error, no warning. If your partition bounds do not cover the actual dates being inserted, the default partition will silently accumulate all the data.

- **Rows in the default partition defeat pruning** - The planner knows the default partition could match any value. It cannot prune the default partition from any query. Even a query filtering on a specific date still scans the default partition.

- **You cannot create a bounded partition if the default already holds overlapping rows** - If `orders_chaos_default` has rows with `order_date = '2024-01-15'`, you cannot create a partition `FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')` - PostgreSQL will refuse because those rows would violate the new bounds. You must move the rows out first.

- **DETACH + recreate is the redistribution pattern** - To fix wrong bounds: (1) detach the default partition to make it a plain table, (2) create the correct bounded partitions, (3) re-insert the rows from the detached default into the parent (they will route to the new partitions), (4) verify the default is empty, then optionally re-attach an empty default.

---

## Diagnostic Steps

### Step 1 - Connect to the database

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Check partition structure

```sql
SELECT
    child.relname AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS bounds,
    COUNT(op.order_id) AS row_count
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
LEFT JOIN orders_chaos op ON op.tableoid = child.oid
WHERE parent.relname = 'orders_chaos'
GROUP BY child.relname, child.relpartbound, child.oid
ORDER BY child.relname;
```

Expected output (yours will differ):

```
    partition_name     |                   bounds                    | row_count
-----------------------+---------------------------------------------+-----------
 orders_chaos_2020_01  | FOR VALUES FROM ('2020-01-01') TO ...       |         0
 orders_chaos_2020_02  | FOR VALUES FROM ('2020-02-01') TO ...       |         0
 orders_chaos_default  | DEFAULT                                      |      5000
(3 rows)
```

The bounded partitions are empty. All 5000 rows are in the default partition.

### Step 3 - Check the actual date range of data in the default partition

```sql
SELECT MIN(order_date), MAX(order_date), COUNT(*)
FROM orders_chaos_default;
```

Expected output (yours will differ):

```
    min     |    max     | count
------------+------------+-------
 2024-01-01 | 2024-03-31 |  5000
(1 row)
```

The data spans 2024-01-01 to 2024-03-31. You need to create partitions for January, February, and March 2024.

### Step 4 - Prove pruning is broken with EXPLAIN

```sql
EXPLAIN
SELECT COUNT(*) FROM orders_chaos
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';
```

Expected output (yours will differ):

```
 Append  (cost=...)
   ->  Seq Scan on orders_chaos_2020_01
   ->  Seq Scan on orders_chaos_2020_02
   ->  Seq Scan on orders_chaos_default   <-- all rows here, full scan
```

The default partition is always scanned because it could match any date.

---

## Resolution

### Step 1 - Detach the default partition

Detach the default partition to make it a standalone table:

```sql
ALTER TABLE orders_chaos
    DETACH PARTITION orders_chaos_default CONCURRENTLY;
```

### Step 2 - Create correct bounded partitions

```sql
CREATE TABLE orders_chaos_2024_01
    PARTITION OF orders_chaos
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

```sql
CREATE TABLE orders_chaos_2024_02
    PARTITION OF orders_chaos
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
```

```sql
CREATE TABLE orders_chaos_2024_03
    PARTITION OF orders_chaos
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
```

### Step 3 - Re-insert data from the detached default into the parent

The parent will now route rows to the correct partitions:

```sql
INSERT INTO orders_chaos
SELECT * FROM orders_chaos_default;
```

### Step 4 - Verify the default partition is now empty

```sql
SELECT COUNT(*) FROM orders_chaos_default;
```

Expected output:

```
 count
-------
     0
(1 row)
```

### Step 5 - Re-attach an empty default partition for future safety

```sql
ALTER TABLE orders_chaos
    ATTACH PARTITION orders_chaos_default
    DEFAULT;
```

### Step 6 - Prove pruning is working

```sql
EXPLAIN
SELECT COUNT(*) FROM orders_chaos
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';
```

Expected output (yours will differ):

```
 Aggregate  (cost=...)
   ->  Seq Scan on orders_chaos_2024_01
```

Only the January 2024 partition appears. Pruning is working.

### Step 7 - Verify row count integrity

```sql
SELECT COUNT(*) FROM orders_chaos;
```

Confirm the count matches the 5000 rows that were originally inserted.

```bash
exit
```

---

## Validation

Run the validation script from the survive directory:

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- orders_chaos has correct bounded partitions for 2024
- Default partition has zero rows
- EXPLAIN shows pruning is working (only one partition scanned for a single-month filter)
- Total row count matches original injection count

---

## Interview Discussion Points

1. **How does PostgreSQL decide which partition to use for an insert?** - For RANGE partitions, PostgreSQL evaluates the row's partition key value against the bounds of each partition in order. The first partition whose bounds include the value receives the row. If no partition matches, the row goes to the default partition (if one exists) or the insert fails.

2. **Why does the default partition always get scanned even if no data is in it?** - The default partition's implicit constraint is "all values not covered by bounded partitions." PostgreSQL cannot prune it without examining it, because a new bounded partition might have been added since the plan was created. Even an empty default partition adds overhead.

3. **What is the right monitoring check to catch this problem before it accumulates?** - Monitor the row count in the default partition with a scheduled query or alert: `SELECT COUNT(*) FROM orders_chaos_default`. If this returns anything other than zero, it means rows are landing where they should not. Set an alert threshold of 0 and page on-call immediately.

4. **Why can you not just CREATE the bounded partition directly when the default already has rows in the same range?** - PostgreSQL enforces that partition bounds cannot overlap. The default partition's constraint covers all values not in bounded partitions. If you try to create a partition covering dates already present in the default, PostgreSQL refuses with: `ERROR: updated partition constraint for default partition "..." would be violated by some row`. You must detach the default first.

5. **What would a pg_partman-managed table do differently?** - pg_partman creates partitions in advance (configurable lead time) and never relies on the default partition for production data. It also has a `run_maintenance()` function that monitors and creates upcoming partitions automatically. The default partition in a pg_partman setup is truly a safety net, not a data store.
