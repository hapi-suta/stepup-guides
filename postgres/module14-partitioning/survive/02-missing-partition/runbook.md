# Scenario 02 - Missing Partition

**Severity:** CRITICAL
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: orders_chaos2 insert pipeline is failing.
ERROR: no partition of relation found for row
DETAIL: order_date 2024-03-xx has no matching partition.
The March 2024 partition was never created.
Fix: create the missing partition, then replay failed rows.
```

---

## Key Concepts for Revision

- **No partition = insert failure (without default)** - Unlike a missing index (which just makes queries slow), a missing partition causes hard insert failures. Any row whose partition key falls outside all partition bounds raises: `ERROR: no partition of relation "table" found for row`. The application sees this as a failed transaction.

- **The fix is immediate** - Creating the missing partition is instantaneous and does not require downtime. Once the partition exists, the application can retry the failed inserts immediately.

- **Partition gaps are silent until they are not** - If your partition management script skips a month, you will not notice until a row arrives with that month's date. This is why monitoring the "days until next partition gap" is important in production.

- **Replay responsibility** - Rows that failed to insert are NOT automatically retried. Your application must detect the error and retry, or you must identify the failed rows from application logs and replay them manually.

---

## Diagnostic Steps

### Step 1 - Confirm the error

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Reproduce the error by attempting to insert a March 2024 row:

```sql
INSERT INTO orders_chaos2 (order_id, customer_id, order_date, status, total_amount, region)
VALUES (99999, 1, '2024-03-15', 'pending', 100.00, 'Northeast');
```

Expected output:

```
ERROR:  no partition of relation "orders_chaos2" found for row
DETAIL:  Partition key of the failing row contains (order_date) = (2024-03-15).
```

### Step 2 - Identify the gap

```sql
SELECT
    child.relname AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS bounds
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_chaos2'
ORDER BY child.relname;
```

Expected output (yours will differ):

```
     partition_name      |                   bounds
-------------------------+----------------------------------------------
 orders_chaos2_2024_01   | FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')
 orders_chaos2_2024_02   | FOR VALUES FROM ('2024-02-01') TO ('2024-03-01')
 orders_chaos2_2024_04   | FOR VALUES FROM ('2024-04-01') TO ('2024-05-01')
(3 rows)
```

The gap is clear: nothing covers '2024-03-01' TO '2024-04-01'.

---

## Resolution

### Step 1 - Create the missing March 2024 partition

```sql
CREATE TABLE orders_chaos2_2024_03
    PARTITION OF orders_chaos2
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
```

Expected output:

```
CREATE TABLE
```

### Step 2 - Verify the partition was created

```sql
SELECT
    child.relname AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS bounds
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_chaos2'
ORDER BY child.relname;
```

Expected output (yours will differ):

```
     partition_name      |                   bounds
-------------------------+----------------------------------------------
 orders_chaos2_2024_01   | FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')
 orders_chaos2_2024_02   | FOR VALUES FROM ('2024-02-01') TO ('2024-03-01')
 orders_chaos2_2024_03   | FOR VALUES FROM ('2024-03-01') TO ('2024-04-01')
 orders_chaos2_2024_04   | FOR VALUES FROM ('2024-04-01') TO ('2024-05-01')
(4 rows)
```

### Step 3 - Confirm inserts now succeed

```sql
INSERT INTO orders_chaos2 (order_id, customer_id, order_date, status, total_amount, region)
VALUES (99999, 1, '2024-03-15', 'pending', 100.00, 'Northeast');
```

Expected output:

```
INSERT 0 1
```

### Step 4 - Replay March 2024 data from the source table

In a real scenario, you would replay from the application's failed-transaction log. Here you load from the source `orders` table:

```sql
INSERT INTO orders_chaos2
SELECT order_id, customer_id, order_date, status, total_amount, region
FROM orders
WHERE order_date >= '2024-03-01' AND order_date < '2024-04-01'
AND order_id NOT IN (SELECT order_id FROM orders_chaos2);
```

### Step 5 - Verify March data landed in the correct partition

```sql
SELECT COUNT(*), MIN(order_date), MAX(order_date)
FROM orders_chaos2_2024_03;
```

Confirm dates are all within March 2024.

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## Validation

Run the validation script:

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- orders_chaos2_2024_03 partition exists
- Inserts into March 2024 succeed
- March partition has rows
- No insert errors on replay

---

## Interview Discussion Points

1. **How would you detect a partition gap before it causes insert failures in production?** - Run a scheduled check that compares the current date + 30 days against the maximum partition upper bound. If `CURRENT_DATE + INTERVAL '30 days' > MAX(upper_bound)`, alert immediately. Example query: `SELECT MAX(pg_get_expr(relpartbound, oid)) FROM pg_class WHERE relname LIKE 'orders_%' AND relkind = 'r'`. A simpler check: verify the partition for next month exists on the 25th of each month.

2. **What happens to rows that failed to insert? Does PostgreSQL retry them?** - PostgreSQL does not retry failed inserts. The application receives the error and is responsible for retry logic. In a well-designed system, the application catches `no partition found` errors and queues the failed rows for replay after the DBA creates the missing partition. In practice, this often means replaying from the original data source (a message queue, a CDC log, or the source table).

3. **Can you create a partition while the table is receiving inserts?** - Yes. `CREATE TABLE ... PARTITION OF` is an online operation. It takes a brief `ACCESS EXCLUSIVE` lock on the parent table to register the new partition, then releases it. Inserts can proceed normally immediately after. In practice, the lock duration is milliseconds.

4. **If you have a default partition, does this scenario still cause failures?** - No. With a default partition, rows with no matching bounded partition land in the default instead of failing. However, those rows then need to be moved to the correct partition once you create it. The default partition prevents downtime at the cost of needing remediation work later.

5. **How does pg_partman prevent this scenario?** - pg_partman creates partitions in advance based on a configurable `premake` setting (default: 4 future periods). If you are using monthly partitions, pg_partman creates the next 4 months of partitions automatically. It runs as a background worker or via a cron-triggered `run_maintenance()` call. Missing partitions are essentially impossible as long as maintenance runs.
