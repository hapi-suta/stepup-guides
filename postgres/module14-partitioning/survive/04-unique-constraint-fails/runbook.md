# Scenario 04 - Unique Constraint Fails

**Severity:** MEDIUM
**Expected Recovery Time:** 10-15 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Developer request - add UNIQUE(order_id) to orders_chaos4.
All attempts are failing with:
ERROR: unique constraint on partitioned table must include all partitioning columns
Diagnose the constraint design issue and implement a working uniqueness strategy.
```

---

## Key Concepts for Revision

- **Unique constraints must include the partition key** - PostgreSQL enforces uniqueness per-partition. To guarantee global uniqueness across all partitions, the constraint must include the partition key column(s). This ensures that any given `(order_id, order_date)` combination can only route to one partition, making per-partition uniqueness equivalent to global uniqueness.

- **This is a schema design decision, not a bug** - The restriction exists because PostgreSQL cannot check uniqueness across multiple physical tables (partitions) efficiently. Including the partition key in the unique constraint is the architectural solution, not a workaround.

- **Application impact** - If your application relies on querying by `order_id` alone (e.g., `WHERE order_id = ?`), you must also pass `order_date` in that query when the table is partitioned - otherwise every partition gets scanned. This changes your application's query pattern.

- **Alternative: keep the sequence in the parent** - If `order_id` comes from a sequence (serial/bigserial), the sequence still guarantees globally unique IDs. The unique constraint on `(order_id, order_date)` enforces that no two orders share both the same ID AND the same date - which is practically equivalent for most use cases since IDs are already unique from the sequence.

---

## Diagnostic Steps

### Step 1 - Reproduce the error

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Try adding the unique constraint on `order_id` alone:

```sql
ALTER TABLE orders_chaos4
    ADD CONSTRAINT uq_chaos4_order_id UNIQUE (order_id);
```

Expected output:

```
ERROR:  unique constraint on partitioned table must include all partitioning columns
DETAIL:  UNIQUE constraint on table "orders_chaos4" lacks column "order_date" which is part of the partition key.
```

### Step 2 - Understand the partition key

```sql
SELECT pg_get_partkeydef('orders_chaos4'::regclass);
```

Expected output:

```
 pg_get_partkeydef
-------------------
 RANGE (order_date)
(1 row)
```

The partition key is `order_date`. Any unique constraint must include `order_date`.

### Step 3 - Check for duplicate order_ids that would violate the constraint

```sql
SELECT order_id, COUNT(*) AS cnt
FROM orders_chaos4
GROUP BY order_id
HAVING COUNT(*) > 1
LIMIT 5;
```

Expected output (yours will differ):

```
 order_id | cnt
----------+-----
(0 rows)
```

No duplicates - the data is clean. The constraint will succeed once the partition key is included.

---

## Resolution

### Step 1 - Add the unique constraint including the partition key

```sql
ALTER TABLE orders_chaos4
    ADD CONSTRAINT uq_chaos4_order_id_date UNIQUE (order_id, order_date);
```

Expected output:

```
ALTER TABLE
```

### Step 2 - Verify the constraint is in place

```sql
SELECT conname, contype, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'orders_chaos4'::regclass
AND contype = 'u';
```

Expected output (yours will differ):

```
         conname          | contype |               definition
--------------------------+---------+----------------------------------------------
 uq_chaos4_order_id_date  |   u     | UNIQUE (order_id, order_date)
(1 row)
```

### Step 3 - Prove the constraint works

Insert a row:

```sql
INSERT INTO orders_chaos4 (order_id, customer_id, order_date, status, total_amount, region)
VALUES (99999900, 1, '2024-01-15', 'pending', 100.00, 'West');
```

Try to insert the same `(order_id, order_date)` again - this should fail:

```sql
INSERT INTO orders_chaos4 (order_id, customer_id, order_date, status, total_amount, region)
VALUES (99999900, 2, '2024-01-15', 'completed', 200.00, 'Northeast');
```

Expected output:

```
ERROR:  duplicate key value violates unique constraint "orders_chaos4_2024_01_order_id_order_date_key"
DETAIL:  Key (order_id, order_date)=(99999900, 2024-01-15) already exists.
```

Insert the same `order_id` with a DIFFERENT `order_date` - this should succeed (different partition):

```sql
INSERT INTO orders_chaos4 (order_id, customer_id, order_date, status, total_amount, region)
VALUES (99999900, 1, '2024-02-15', 'pending', 100.00, 'West');
```

Expected output:

```
INSERT 0 1
```

> **This is the key trade-off**: the constraint `UNIQUE(order_id, order_date)` prevents duplicate `(order_id, order_date)` pairs but allows the same `order_id` to appear in different months. If your application requires globally unique `order_id` values across all time, you need a separate sequence and application-level enforcement, or a non-partitioned lookup table.

Clean up test rows:

```sql
DELETE FROM orders_chaos4 WHERE order_id = 99999900;
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

## Validation

Run the validation script:

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- UNIQUE constraint exists on orders_chaos4 including order_date
- Duplicate (order_id, order_date) insert is rejected
- Different order_date with same order_id is allowed

---

## Interview Discussion Points

1. **Why does PostgreSQL require the partition key in unique constraints?** - Each partition is a physical table. PostgreSQL enforces unique constraints within each physical table independently. Without the partition key in the constraint, two rows with the same `order_id` but different `order_date` values could land in different partitions and both pass their local uniqueness checks - creating a global duplicate. Including the partition key ensures any given `(order_id, order_date)` combination can only route to one partition, making per-partition uniqueness globally sound.

2. **What if the application truly requires globally unique order IDs, regardless of date?** - Three options: (1) Use a separate non-partitioned sequence table that generates IDs - the application queries this first to get an ID, then inserts with that ID into the partitioned table. (2) Use UUIDs generated application-side (v4 UUIDs are globally unique by design). (3) Keep the order ID lookup in a separate non-partitioned table (an index-only table with `order_id` and `order_date`) and use application logic to enforce cross-partition uniqueness. None of these options are as elegant as a simple UNIQUE constraint.

3. **Does PRIMARY KEY have the same restriction?** - Yes. PRIMARY KEY is implemented as a UNIQUE NOT NULL constraint. It must also include all partition key columns. This is the most common surprise for developers migrating a table to partitioned: their existing `PRIMARY KEY (order_id)` definition must become `PRIMARY KEY (order_id, order_date)`.

4. **What happens when you query by order_id alone on a table with this constraint?** - `SELECT * FROM orders_chaos4 WHERE order_id = 12345` cannot use the partition key for pruning - all partitions are scanned. This is a query performance regression. The workaround is to always include `order_date` in queries: `WHERE order_id = 12345 AND order_date = '2024-01-15'`. This requires the application to know the order date when looking up by ID.

5. **Can you use a global sequence to generate order IDs and still have them be unique across partitions?** - Yes. A PostgreSQL sequence (`SERIAL` or `CREATE SEQUENCE`) is a global object - it guarantees each call to `nextval()` returns a unique value, regardless of which partition receives the row. The sequence alone prevents duplicate IDs from being generated. The UNIQUE constraint on `(order_id, order_date)` is then an additional safety net that prevents the same ID from being inserted twice with the same date.
