# BUILD 04: Zero-Downtime Migrations

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster
**Estimated Time:** 60-75 minutes

---

## What You Will Learn

How to apply schema changes to a production Aurora PostgreSQL database without causing downtime - no locked tables, no blocked queries, no angry application teams.

---

## Prerequisites

- Aurora PostgreSQL cluster (`devops-lab-cluster`) running
- Completed BUILD 01-03
- `psql` installed on your Mac

---

## Why ALTER TABLE Can Lock Your Database

When you run `ALTER TABLE` in PostgreSQL (and Aurora PostgreSQL), the database acquires locks. The type of lock depends on the operation:

| Operation | Lock Level | Impact |
|-----------|-----------|--------|
| `ADD COLUMN` (no default) | `ACCESS EXCLUSIVE` | Blocks all reads and writes (brief) |
| `ADD COLUMN DEFAULT` (PG 11+/Aurora) | `ACCESS EXCLUSIVE` | Brief lock - no table rewrite |
| `DROP COLUMN` | `ACCESS EXCLUSIVE` | Brief lock (marks column as dropped) |
| `ALTER COLUMN TYPE` | `ACCESS EXCLUSIVE` | May rewrite table - long lock |
| `CREATE INDEX` | `SHARE` | Blocks writes, allows reads |
| `CREATE INDEX CONCURRENTLY` | Weak locks | Allows reads AND writes |
| `ADD CONSTRAINT NOT VALID` | `ACCESS EXCLUSIVE` | Brief lock, no table scan |
| `VALIDATE CONSTRAINT` | `SHARE UPDATE EXCLUSIVE` | Allows reads and writes |

The problem is not the lock itself - it is the **lock queue**. When a statement requests an `ACCESS EXCLUSIVE` lock, it queues behind any existing transaction. While it waits, every new query also queues behind it. One slow ALTER TABLE can cascade into blocking every query on that table.

---

## Step 1: Set Up a Test Environment

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "CREATE DATABASE zerodt_lab;"
```

Expected output:
```
CREATE DATABASE
```

Create a table with sample data:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d zerodt_lab
```

Inside psql, run:

```sql
CREATE TABLE customers (
    customer_id  SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    email        VARCHAR(255),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

```sql
INSERT INTO customers (name, email)
SELECT
    'Customer ' || i,
    'customer' || i || '@example.com'
FROM generate_series(1, 500000) AS i;
```

- `generate_series(1, 500000)` creates 500,000 rows. This gives us enough data to see locking behavior.

Expected output (yours will differ):
```
INSERT 0 500000
```

Verify:

```sql
SELECT count(*) FROM customers;
```

Expected output:
```
  count
--------
 500000
```

Stay in psql for the next steps.

---

## Step 2: Safe Column Addition (Aurora/PG 11+)

Aurora PostgreSQL is based on PostgreSQL 11+, which means `ADD COLUMN ... DEFAULT value` is nearly instant. It does not rewrite the table.

```sql
\timing on
```

- `\timing on` - shows how long each command takes.

```sql
ALTER TABLE customers ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
```

Expected output (yours will differ):
```
ALTER TABLE
Time: 5.234 ms
```

5 milliseconds for 500,000 rows. The lock is acquired and released almost instantly because Aurora does not rewrite the table.

```sql
SELECT customer_id, name, status FROM customers LIMIT 3;
```

Expected output:
```
 customer_id |    name     | status
-------------+-------------+--------
           1 | Customer 1  | active
           2 | Customer 2  | active
           3 | Customer 3  | active
```

```sql
\timing off
```

---

## Step 3: CREATE INDEX CONCURRENTLY

Creating an index normally acquires a `SHARE` lock, which blocks all writes for the duration of the index build. On a large table, this can take minutes.

`CREATE INDEX CONCURRENTLY` builds the index without blocking writes. It takes longer but the table remains fully available.

```sql
\timing on
```

Standard index (blocks writes during build):

```sql
CREATE INDEX idx_customers_email ON customers (email);
```

Expected output (yours will differ):
```
CREATE INDEX
Time: 423.456 ms
```

Drop it so we can create it concurrently:

```sql
DROP INDEX idx_customers_email;
```

Concurrent index (allows writes during build):

```sql
CREATE INDEX CONCURRENTLY idx_customers_email ON customers (email);
```

Expected output (yours will differ):
```
CREATE INDEX
Time: 789.123 ms
```

The concurrent version takes longer but allows all reads and writes while building.

```sql
\timing off
```

**Key rules for CREATE INDEX CONCURRENTLY:**

1. It cannot run inside a transaction block. If your migration tool wraps everything in a transaction, you must disable that.
2. If it fails halfway, it leaves an `INVALID` index behind. Check with:

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'customers' AND indexname LIKE 'idx_%';
```

3. In Flyway, add this directive at the top of your migration file:

```sql
-- flyway:executeInTransaction=false
```

This tells Flyway not to wrap the migration in a transaction, which is required for CONCURRENTLY to work.

---

## Step 4: Adding Constraints Safely

Adding a `CHECK` constraint normally scans the entire table while holding a lock. The safe pattern uses two steps.

### Step 4a: Add the Constraint as NOT VALID

```sql
\timing on
```

```sql
ALTER TABLE customers ADD CONSTRAINT chk_email_not_empty
    CHECK (email IS NOT NULL AND email <> '') NOT VALID;
```

- `NOT VALID` - adds the constraint to the catalog (enforced for new/updated rows) without scanning existing rows. This is fast.

Expected output (yours will differ):
```
ALTER TABLE
Time: 2.345 ms
```

### Step 4b: Validate the Constraint Separately

```sql
ALTER TABLE customers VALIDATE CONSTRAINT chk_email_not_empty;
```

- `VALIDATE CONSTRAINT` - scans all existing rows but uses a `SHARE UPDATE EXCLUSIVE` lock, which allows concurrent reads and writes.

Expected output (yours will differ):
```
ALTER TABLE
Time: 345.678 ms
```

The validation takes longer because it scans every row, but the table remains fully available during the scan.

```sql
\timing off
```

---

## Step 5: The Expand-Contract Pattern

The expand-contract pattern is the fundamental strategy for zero-downtime migrations. It has three phases.

### Phase 1: Expand

Add new structures alongside old ones. Both old and new application code can work.

### Phase 2: Migrate

Move data from old structures to new ones. Both code paths still work.

### Phase 3: Contract

Remove old structures after all code has been updated.

### Example: Splitting a Column

You need to split the `name` column into `first_name` and `last_name`.

**Bad approach (causes downtime):**

```sql
-- Blocks everything and breaks code using "name"
ALTER TABLE customers RENAME COLUMN name TO full_name;
```

**Good approach (expand-contract):**

**Migration V6 - Expand (add new columns):**

```bash
vi V6__add_name_columns.sql
```

```sql
-- Phase 1: EXPAND - add new columns alongside the old one
SET lock_timeout = '5s';
ALTER TABLE customers ADD COLUMN first_name VARCHAR(50);
ALTER TABLE customers ADD COLUMN last_name VARCHAR(50);
```

**Migration V7 - Migrate (backfill data in batches):**

```bash
vi V7__backfill_name_columns.sql
```

```sql
-- Phase 2: MIGRATE - backfill data in batches
DO $$
DECLARE
    batch_size INT := 10000;
    rows_updated INT := 1;
    total_updated INT := 0;
BEGIN
    WHILE rows_updated > 0 LOOP
        UPDATE customers
        SET
            first_name = split_part(name, ' ', 1),
            last_name  = split_part(name, ' ', 2)
        WHERE customer_id IN (
            SELECT customer_id
            FROM customers
            WHERE first_name IS NULL
            LIMIT batch_size
        );

        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        total_updated := total_updated + rows_updated;
        RAISE NOTICE 'Updated % rows (total: %)', rows_updated, total_updated;
        PERFORM pg_sleep(0.1);
    END LOOP;

    RAISE NOTICE 'Backfill complete. Total: %', total_updated;
END $$;
```

- `batch_size INT := 10000` - update 10,000 rows at a time to minimize lock duration.
- `PERFORM pg_sleep(0.1)` - pause 100ms between batches to let other transactions through.
- `GET DIAGNOSTICS rows_updated = ROW_COUNT` - captures how many rows the UPDATE affected.

**Migration V8 - Add constraints:**

```bash
vi V8__add_name_constraints.sql
```

```sql
-- Add NOT NULL constraints using the safe two-step pattern
SET lock_timeout = '5s';

ALTER TABLE customers ADD CONSTRAINT chk_first_name_nn
    CHECK (first_name IS NOT NULL) NOT VALID;
ALTER TABLE customers VALIDATE CONSTRAINT chk_first_name_nn;

ALTER TABLE customers ADD CONSTRAINT chk_last_name_nn
    CHECK (last_name IS NOT NULL) NOT VALID;
ALTER TABLE customers VALIDATE CONSTRAINT chk_last_name_nn;
```

**Migration V9 - Contract (drop old column):**

```bash
vi V9__drop_old_name_column.sql
```

```sql
-- Phase 3: CONTRACT - remove old column
-- Only deploy this AFTER all application code uses first_name/last_name
SET lock_timeout = '5s';
ALTER TABLE customers DROP COLUMN name;
```

**Important:** Do not deploy V9 until the application has been fully updated. The expand-contract pattern gives you a window where both old and new columns exist.

---

## Step 6: Run the Migration Sequence

Exit psql if you are still in it:

```sql
\q
```

Run the expand migration:

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d zerodt_lab -f V6__add_name_columns.sql
```

Expected output:
```
SET
ALTER TABLE
ALTER TABLE
```

Run the backfill:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d zerodt_lab -f V7__backfill_name_columns.sql
```

Expected output (yours will differ):
```
NOTICE:  Updated 10000 rows (total: 10000)
NOTICE:  Updated 10000 rows (total: 20000)
...
NOTICE:  Updated 10000 rows (total: 500000)
NOTICE:  Updated 0 rows (total: 500000)
NOTICE:  Backfill complete. Total: 500000
DO
```

Verify the backfill:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d zerodt_lab -c "SELECT customer_id, name, first_name, last_name FROM customers LIMIT 5;"
```

Expected output:
```
 customer_id |     name     | first_name | last_name
-------------+--------------+------------+-----------
           1 | Customer 1   | Customer   | 1
           2 | Customer 2   | Customer   | 2
           3 | Customer 3   | Customer   | 3
           4 | Customer 4   | Customer   | 4
           5 | Customer 5   | Customer   | 5
```

Both old (`name`) and new (`first_name`, `last_name`) columns coexist. The application can be gradually updated.

---

## Step 7: Lock Timeout Safety Net

Always set a lock timeout when running migrations on production. If the lock cannot be acquired within the timeout, the migration aborts instead of blocking the lock queue.

```sql
SET lock_timeout = '5s';

ALTER TABLE customers ADD COLUMN phone VARCHAR(20);
```

If the lock times out:

```
ERROR:  canceling statement due to lock timeout
```

This prevents the cascading lock queue problem. It is better to fail fast and retry later than to block all queries.

**Add these two lines to the top of every production migration file:**

```sql
SET lock_timeout = '5s';
SET statement_timeout = '300s';
```

- `lock_timeout = '5s'` - abort if the lock is not acquired in 5 seconds.
- `statement_timeout = '300s'` - abort if the statement runs longer than 5 minutes.

---

## Step 8: Monitor Long-Running Operations

Aurora PostgreSQL provides progress monitoring for index creation.

Open two terminal windows.

**Terminal 1 - create a large index:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d zerodt_lab -c "CREATE INDEX CONCURRENTLY idx_customers_name ON customers (name);"
```

**Terminal 2 (while Terminal 1 is running):**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d zerodt_lab -c "
SELECT
    phase,
    blocks_total,
    blocks_done,
    CASE WHEN blocks_total > 0
         THEN round(100.0 * blocks_done / blocks_total, 1)
         ELSE 0
    END AS pct_done
FROM pg_stat_progress_create_index;
"
```

Expected output (yours will differ):
```
        phase         | blocks_total | blocks_done | pct_done
----------------------+--------------+-------------+----------
 building index: scanning table |        4167 |        2260 |     54.2
```

This lets you see exactly where a long-running operation stands instead of wondering "is it still going?"

---

## Step 9: Zero-Downtime Patterns Cheat Sheet

Use this as a quick reference when writing migrations.

| Pattern | Safe DDL |
|---------|----------|
| Add column | `ALTER TABLE t ADD COLUMN c TYPE DEFAULT val;` (instant on Aurora) |
| Add index | `CREATE INDEX CONCURRENTLY idx ON t (c);` (requires `executeInTransaction=false`) |
| Add constraint | `ADD CONSTRAINT ... NOT VALID;` then `VALIDATE CONSTRAINT ...;` |
| Add NOT NULL | Add CHECK `(col IS NOT NULL) NOT VALID`, validate, then `SET NOT NULL` |
| Rename column | Expand-contract: add new, backfill, drop old |
| Change type | Expand-contract: add new column with new type, backfill, drop old |
| Backfill data | Batched updates (10K rows), `pg_sleep(0.1)` between batches |
| Safety net | `SET lock_timeout = '5s'; SET statement_timeout = '300s';` |

---

## Step 10: Clean Up

Drop the test database when you are done:

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "DROP DATABASE IF EXISTS zerodt_lab;"
```

Expected output:
```
DROP DATABASE
```

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Lock levels | ALTER TABLE acquires ACCESS EXCLUSIVE - blocks everything |
| Lock queue cascade | Pending locks block all subsequent queries |
| Expand-contract | Add new, migrate data, remove old - three separate migrations |
| CREATE INDEX CONCURRENTLY | Builds indexes without blocking writes |
| ADD COLUMN DEFAULT (Aurora) | Nearly instant - no table rewrite |
| NOT VALID constraints | Add constraint without scanning, validate separately |
| Batched backfills | Update 10K rows at a time to minimize lock duration |
| lock_timeout | Fail fast if locks cannot be acquired |
| pg_stat_progress_create_index | Monitor long-running index builds |
| statement_timeout | Kill long-running statements automatically |

---

**Next:** [BUILD 05: Rollback Strategies](05-rollback-strategies.md) - when and how to undo a migration that went wrong.
