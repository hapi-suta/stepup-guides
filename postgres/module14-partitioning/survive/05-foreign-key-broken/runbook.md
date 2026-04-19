# Scenario 05 - Foreign Key Broken

**Severity:** HIGH
**Expected Recovery Time:** 10-15 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application errors on the orders system.
Some queries on line_items are returning FK violation
errors. A partition maintenance job detached February's
partition but there are line_items referencing orders
in that month. The detached partition still exists as
a standalone table but is no longer part of the
partitioned hierarchy.
```

---

## Key Concepts for Revision

- **Detaching a partition removes it from the partition hierarchy** - `ALTER TABLE ... DETACH PARTITION` makes the partition a standalone table. It is no longer visible through the parent table. However, the physical table and its data remain intact. Foreign keys referencing the parent table may break because the rows are no longer "in" the parent table from the FK constraint's perspective.

- **FK constraints on partitioned tables check via the parent** - When `chaos5_line_items` has a FK referencing `chaos5_orders(id, order_date)`, PostgreSQL validates the reference against the parent table (which includes all attached partitions). After detaching a partition, rows that were in that partition are no longer reachable through the parent, causing FK violations for existing references.

- **ATTACH PARTITION is the reverse of DETACH** - `ALTER TABLE ... ATTACH PARTITION ... FOR VALUES FROM ... TO ...` re-attaches a standalone table as a partition. PostgreSQL validates that all rows in the table satisfy the partition constraint before attaching. This can be slow for large tables.

- **DETACH CONCURRENTLY avoids locks** - In PG 14+, `DETACH PARTITION CONCURRENTLY` uses a two-phase process that avoids blocking queries. However, it still breaks FK references if dependent rows exist.

- **Partition maintenance must consider FK dependencies** - Before detaching or dropping a partition, check for FK references from other tables. Use `pg_constraint` to find all FK relationships. A safe workflow: (1) Delete or migrate dependent rows. (2) Detach the partition. (3) Archive or drop the standalone table.

---

## Diagnostic Steps

### Step 1 - Check for FK violation errors

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Try inserting a line item that references a February order:

```sql
SELECT id, order_date FROM chaos5_orders WHERE order_date >= '2024-02-01' AND order_date < '2024-03-01' LIMIT 1;
```

Expected output:

```
 id | order_date
----+------------
(0 rows)
```

No February orders are visible through the parent table - they were in the detached partition.

### Step 2 - Check if the detached partition still exists as a standalone table

```sql
SELECT relname, relkind
FROM pg_class
WHERE relname LIKE 'chaos5_orders_2024_02';
```

Expected output:

```
        relname        | relkind
-----------------------+---------
 chaos5_orders_2024_02 | r
(1 row)
```

The table exists (`relkind = 'r'` means regular table, not `p` for partitioned). It was detached.

### Step 3 - Verify data is still in the detached table

```sql
SELECT count(*) FROM chaos5_orders_2024_02;
```

Expected output (yours will differ):

```
 count
-------
  1000
(1 row)
```

The data is intact in the standalone table.

### Step 4 - Check which partitions are currently attached

```sql
SELECT inhrelid::regclass AS partition_name
FROM pg_inherits
WHERE inhparent = 'chaos5_orders'::regclass
ORDER BY partition_name;
```

Expected output:

```
     partition_name
------------------------
 chaos5_orders_2024_01
 chaos5_orders_2024_03
(2 rows)
```

February is missing from the partition list.

### Step 5 - Check FK dependencies

```sql
SELECT
  conname,
  conrelid::regclass AS referencing_table,
  confrelid::regclass AS referenced_table
FROM pg_constraint
WHERE confrelid = 'chaos5_orders'::regclass
AND contype = 'f';
```

Expected output (yours will differ):

```
          conname           |  referencing_table  | referenced_table
----------------------------+---------------------+------------------
 chaos5_line_items_..._fkey | chaos5_line_items   | chaos5_orders
(1 row)
```

`chaos5_line_items` has a FK to `chaos5_orders`. Some of its rows reference orders that are now in the detached partition.

---

## Resolution

### Step 1 - Re-attach the partition

```sql
ALTER TABLE chaos5_orders
    ATTACH PARTITION chaos5_orders_2024_02
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
```

Expected output:

```
ALTER TABLE
```

PostgreSQL validates that all rows in `chaos5_orders_2024_02` satisfy the range constraint before attaching.

### Step 2 - Verify the partition is re-attached

```sql
SELECT inhrelid::regclass AS partition_name
FROM pg_inherits
WHERE inhparent = 'chaos5_orders'::regclass
ORDER BY partition_name;
```

Expected output:

```
     partition_name
------------------------
 chaos5_orders_2024_01
 chaos5_orders_2024_02
 chaos5_orders_2024_03
(3 rows)
```

All three partitions are attached.

### Step 3 - Verify February orders are visible again

```sql
SELECT count(*) FROM chaos5_orders WHERE order_date >= '2024-02-01' AND order_date < '2024-03-01';
```

Expected output (yours will differ):

```
 count
-------
  1000
(1 row)
```

### Step 4 - Verify FK integrity

```sql
SELECT count(*) FROM chaos5_line_items li
JOIN chaos5_orders o ON o.id = li.order_id AND o.order_date = li.order_date;
```

Expected output (yours will differ):

```
 count
-------
   500
(1 row)
```

All line items can now join back to their orders. No FK violations.

### Step 5 - Test a new FK insert works

```sql
INSERT INTO chaos5_line_items (order_id, order_date, product_name, quantity)
SELECT id, order_date, 'Test Product', 1
FROM chaos5_orders
WHERE order_date >= '2024-02-01' AND order_date < '2024-03-01'
LIMIT 1;
```

Expected output:

```
INSERT 0 1
```

Clean up:

```sql
DELETE FROM chaos5_line_items WHERE product_name = 'Test Product';
```

```sql
\q
```

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- chaos5_orders_2024_02 is attached as a partition
- February orders are visible through parent table
- FK join between line_items and orders works
- New FK inserts succeed

---

## Interview Discussion Points

1. **How do you safely detach a partition that has FK references?** - First, identify all tables with FK constraints referencing the partitioned parent. Then either: (1) Migrate dependent rows to reference data in other partitions. (2) Delete the dependent rows. (3) Drop the FK constraint, detach, then recreate the FK. Option 1 is the safest for data integrity. Always run the check query before detaching: `SELECT count(*) FROM child_table WHERE date_column >= partition_start AND date_column < partition_end`.

2. **What is the difference between DETACH PARTITION and DROP PARTITION?** - There is no `DROP PARTITION` command. You detach first, then drop the standalone table: `ALTER TABLE parent DETACH PARTITION child; DROP TABLE child;`. Detaching keeps the data as a standalone table (useful for archiving). Dropping after detaching permanently deletes the data.

3. **Does ATTACH PARTITION validate all rows?** - Yes, by default. PostgreSQL scans the entire table to verify every row satisfies the partition constraint. For large tables, this can take minutes and holds an AccessExclusive lock. To avoid the scan, you can add a CHECK constraint matching the partition bounds before attaching, and PostgreSQL will skip the validation.

4. **Can you have foreign keys TO a partitioned table?** - Yes, since PG 12. Foreign keys can reference a partitioned table's primary key (which must include the partition key). PostgreSQL automatically propagates the FK constraint to each partition. When a partition is detached, the FK references to rows in that partition become invalid.

5. **What is the risk of DETACH CONCURRENTLY?** - `DETACH CONCURRENTLY` (PG 14+) avoids holding an AccessExclusive lock for the full duration, but it has two phases. Between phases, the partition is in a "detach pending" state. If the session is interrupted between phases, the partition is stuck in this state and must be finalized with `ALTER TABLE ... DETACH PARTITION ... FINALIZE`. Also, FK violations can still occur if concurrent transactions reference the detached partition.
