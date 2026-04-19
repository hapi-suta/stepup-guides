# Scenario 08 - Partition Constraint Violation

**Severity:** HIGH
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Invoice inserts are failing with:
ERROR: no partition of relation "chaos8_invoices" found for row
The application is trying to insert April 2024
invoices but they are being rejected. Q1 and Q3
work fine. Q2 and Q4 have no partitions.
There is no default partition to catch overflow.
```

---

## Key Concepts for Revision

- **Partitioned tables reject unroutable rows** - When you insert a row into a partitioned table, PostgreSQL checks which partition should receive it based on the partition key value. If no partition covers that value, PostgreSQL raises `ERROR: no partition of relation found for row`. This is not a bug - it is a constraint enforcement.

- **Default partitions catch overflow** - A default partition (`CREATE TABLE ... PARTITION OF parent DEFAULT`) receives any rows that do not match any other partition's range. Without a default partition, gaps in the partition ranges cause insert failures. Default partitions are a safety net.

- **Gaps in partition ranges are common mistakes** - When partitions are created manually (Q1: Jan-Mar, Q3: Jul-Sep), it is easy to skip quarters. Automation tools like pg_partman prevent gaps by creating partitions ahead of time on a schedule.

- **Creating a new partition is non-blocking** - `CREATE TABLE ... PARTITION OF parent FOR VALUES FROM ... TO ...` is a metadata-only operation that completes instantly and does not lock the parent table for reads or writes. This makes it safe to add missing partitions to a live system.

- **Best practice: always have a default partition** - A default partition ensures inserts never fail due to missing ranges. You can periodically check the default partition for "misrouted" rows and create proper partitions for them. The default partition acts as an alert mechanism - if rows appear there, it means you are missing a partition.

---

## Diagnostic Steps

### Step 1 - Reproduce the error

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
INSERT INTO chaos8_invoices (invoice_date, customer_name, amount)
VALUES ('2024-04-15', 'Test Customer', 100.00);
```

Expected output:

```
ERROR:  no partition of relation "chaos8_invoices" found for row
DETAIL:  Partition key of the failing row contains (invoice_date) = (2024-04-15).
```

### Step 2 - Check which partitions exist

```sql
SELECT
  inhrelid::regclass AS partition_name,
  pg_get_expr(c.relpartbound, c.oid) AS bounds
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'chaos8_invoices'::regclass
ORDER BY partition_name;
```

Expected output:

```
       partition_name       |                         bounds
----------------------------+--------------------------------------------------------
 chaos8_invoices_2024_q1    | FOR VALUES FROM ('2024-01-01') TO ('2024-04-01')
 chaos8_invoices_2024_q3    | FOR VALUES FROM ('2024-07-01') TO ('2024-10-01')
(2 rows)
```

Q2 (Apr-Jun) and Q4 (Oct-Dec) are missing. There is no default partition.

### Step 3 - Check for a default partition

```sql
SELECT inhrelid::regclass AS partition_name
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'chaos8_invoices'::regclass
AND pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT';
```

Expected output:

```
 partition_name
----------------
(0 rows)
```

No default partition exists.

---

## Resolution

### Step 1 - Create the missing Q2 partition (April through June)

```sql
CREATE TABLE chaos8_invoices_2024_q2
    PARTITION OF chaos8_invoices
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');
```

Expected output:

```
CREATE TABLE
```

### Step 2 - Create the missing Q4 partition (October through December)

```sql
CREATE TABLE chaos8_invoices_2024_q4
    PARTITION OF chaos8_invoices
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');
```

Expected output:

```
CREATE TABLE
```

### Step 3 - Create a default partition as a safety net

```sql
CREATE TABLE chaos8_invoices_default
    PARTITION OF chaos8_invoices DEFAULT;
```

Expected output:

```
CREATE TABLE
```

The default partition catches any row that does not fit any other partition (e.g., dates before 2024 or after 2024).

### Step 4 - Verify the April insert now works

```sql
INSERT INTO chaos8_invoices (invoice_date, customer_name, amount)
VALUES ('2024-04-15', 'Test Customer', 100.00);
```

Expected output:

```
INSERT 0 1
```

### Step 5 - Verify October insert works

```sql
INSERT INTO chaos8_invoices (invoice_date, customer_name, amount)
VALUES ('2024-11-20', 'November Customer', 250.00);
```

Expected output:

```
INSERT 0 1
```

### Step 6 - Verify default partition catches out-of-range dates

```sql
INSERT INTO chaos8_invoices (invoice_date, customer_name, amount)
VALUES ('2025-06-01', 'Future Customer', 500.00);
```

Expected output:

```
INSERT 0 1
```

Check the default partition:

```sql
SELECT * FROM chaos8_invoices_default;
```

Expected output (yours will differ):

```
 id  | invoice_date | customer_name   | amount | status
-----+--------------+-----------------+--------+---------
 ... | 2025-06-01   | Future Customer | 500.00 | pending
(1 row)
```

The 2025 row landed in the default partition because no 2025 partition exists.

### Step 7 - Verify all partitions

```sql
SELECT
  inhrelid::regclass AS partition_name,
  pg_get_expr(c.relpartbound, c.oid) AS bounds
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'chaos8_invoices'::regclass
ORDER BY partition_name;
```

Expected output:

```
       partition_name         |                         bounds
------------------------------+--------------------------------------------------------
 chaos8_invoices_2024_q1      | FOR VALUES FROM ('2024-01-01') TO ('2024-04-01')
 chaos8_invoices_2024_q2      | FOR VALUES FROM ('2024-04-01') TO ('2024-07-01')
 chaos8_invoices_2024_q3      | FOR VALUES FROM ('2024-07-01') TO ('2024-10-01')
 chaos8_invoices_2024_q4      | FOR VALUES FROM ('2024-10-01') TO ('2025-01-01')
 chaos8_invoices_default      | DEFAULT
(5 rows)
```

Clean up test rows:

```sql
DELETE FROM chaos8_invoices WHERE customer_name IN ('Test Customer', 'November Customer', 'Future Customer');
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
- Q2 partition exists (April-June range)
- Q4 partition exists (October-December range)
- Default partition exists
- Insert for April date succeeds
- Insert for November date succeeds

---

## Interview Discussion Points

1. **Should you always create a default partition?** - For production tables, yes. A default partition prevents insert failures from unexpected data. It acts as an early warning: if rows appear in the default partition, it means your partition creation process has gaps. Monitor the default partition row count and alert when it exceeds zero. The only downside is that creating a new ranged partition requires first moving any overlapping rows out of the default partition.

2. **What happens when you create a new partition and the default partition has overlapping rows?** - PostgreSQL checks the default partition for rows that would belong in the new partition. If any exist, the `CREATE TABLE ... PARTITION OF` fails with: `ERROR: updated partition constraint for default partition would be violated by some row`. You must move those rows first: `INSERT INTO new_partition SELECT ... FROM default_partition WHERE ...`, then `DELETE FROM default_partition WHERE ...`, then create the new partition.

3. **How does pg_partman prevent this problem?** - pg_partman pre-creates partitions ahead of time (configurable: days, weeks, months ahead). It runs on a schedule (via pg_cron or external cron) and ensures partitions exist before data arrives. It also manages retention: automatically detaching or dropping partitions older than a configured threshold.

4. **What is the performance impact of a default partition?** - Minimal. With partition pruning enabled, queries that target a specific range still prune correctly. The default partition is only scanned when the query's WHERE clause cannot exclude it (e.g., no filter on the partition key). The existence of a default partition does not slow down pruned queries.

5. **Can you create a partitioned table with both RANGE and DEFAULT partitions covering all possible values?** - Yes, and you should. For example: Q1-Q4 range partitions cover 2024, and the default covers everything else. As you add 2025 partitions, move rows from default to the new partitions. This pattern ensures zero insert failures while maintaining clean partition boundaries.
