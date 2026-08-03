# BUILD 03: Zero-Downtime Database Migrations

**Module 05: CI/CD for Database Changes**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to apply schema changes to a production PostgreSQL database without causing downtime - no locked tables, no blocked queries, no angry application teams.

---

## Why ALTER TABLE Can Lock Your Database

When you run `ALTER TABLE` in PostgreSQL, the database acquires locks. The type of lock depends on the operation:

| Operation | Lock Level | Impact |
|-----------|-----------|--------|
| `ADD COLUMN` (no default) | `ACCESS EXCLUSIVE` | Blocks all reads and writes (brief) |
| `ADD COLUMN ... DEFAULT x` (PG 11+) | `ACCESS EXCLUSIVE` | Blocks briefly - does NOT rewrite table |
| `ADD COLUMN ... DEFAULT x` (PG < 11) | `ACCESS EXCLUSIVE` | Rewrites entire table - long lock |
| `DROP COLUMN` | `ACCESS EXCLUSIVE` | Blocks briefly (marks column as dropped) |
| `ALTER COLUMN TYPE` | `ACCESS EXCLUSIVE` | Rewrites table if type change requires it |
| `CREATE INDEX` | `SHARE` lock | Blocks writes, allows reads |
| `CREATE INDEX CONCURRENTLY` | Weaker locks | Allows reads AND writes |
| `ADD CONSTRAINT ... NOT VALID` | `ACCESS EXCLUSIVE` | Brief lock, no table scan |
| `VALIDATE CONSTRAINT` | `SHARE UPDATE EXCLUSIVE` | Allows reads and writes |

The problem is not the lock itself - it is the **lock queue**. In PostgreSQL, when a statement requests an `ACCESS EXCLUSIVE` lock, it queues behind any existing transaction. And while it is waiting, every new query also queues behind it. One slow `ALTER TABLE` can cascade into blocking every query on that table.

**DBA Analogy:** Imagine you need exclusive access to a conference room (the table). You show up and someone has a meeting going on. You wait at the door. But now everyone else who wants to use the room lines up behind you, even though the room is not empty yet. You have not even started your work, but the queue is growing.

---

## Step 1: Set Up a Test Environment

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/zero-downtime
cd ~/dba-labs/zero-downtime
```

Create a test database with sample data:

```bash
psql -U postgres -c "DROP DATABASE IF EXISTS zerodt_lab;"
psql -U postgres -c "CREATE DATABASE zerodt_lab;"
```

```bash
psql -U postgres -d zerodt_lab -c "
CREATE TABLE customers (
    customer_id  SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    email        VARCHAR(255),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Insert 1 million rows for realistic testing
INSERT INTO customers (name, email)
SELECT
    'Customer ' || i,
    'customer' || i || '@example.com'
FROM generate_series(1, 1000000) AS i;
"
```

Expected output (yours will differ):
```
CREATE TABLE
INSERT 0 1000000
```

Verify:

```bash
psql -U postgres -d zerodt_lab -c "SELECT count(*) FROM customers;"
```

Expected output:
```
  count
---------
 1000000
```

---

## Step 2: The Expand-Contract Pattern

The expand-contract pattern (also called "parallel change") is the fundamental strategy for zero-downtime migrations. It has three phases:

### Phase 1: Expand
Add the new structure alongside the old one. Both old and new code can work.

### Phase 2: Migrate
Move data from the old structure to the new one. Old and new code still work.

### Phase 3: Contract
Remove the old structure once all code has been updated. Only new code works.

**DBA Analogy:** Think of it like moving data between tablespaces. You do not drop the old tablespace first - you create the new one, move the data, verify everything works, THEN remove the old one.

### Example: Renaming a Column

You want to rename `name` to `full_name` on the `customers` table.

**Bad approach (causes downtime):**
```sql
-- This acquires ACCESS EXCLUSIVE lock and breaks any code using "name"
ALTER TABLE customers RENAME COLUMN name TO full_name;
```

**Good approach (expand-contract):**

```sql
-- Phase 1: Expand - add new column
ALTER TABLE customers ADD COLUMN full_name VARCHAR(100);

-- Phase 2: Migrate - copy data (in batches)
UPDATE customers SET full_name = name WHERE full_name IS NULL;

-- Phase 3: Contract - drop old column (after all code uses full_name)
ALTER TABLE customers DROP COLUMN name;
```

Each phase is a separate migration. Between phases, you update the application code to use the new column.

---

## Step 3: Safe Column Addition (PostgreSQL 11+)

Before PostgreSQL 11, `ADD COLUMN ... DEFAULT value` rewrote the entire table. On a 100M row table, that meant locking it for minutes.

PostgreSQL 11 changed this. Now, `ADD COLUMN ... DEFAULT value` is nearly instant because PostgreSQL stores the default in the catalog and applies it lazily.

**On your Mac terminal:**

```bash
psql -U postgres -d zerodt_lab
```

Inside psql:

```sql
-- Time a column addition with default on 1M rows
\timing on

ALTER TABLE customers ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
```

Expected output (yours will differ):
```
ALTER TABLE
Time: 4.567 ms
```

4 milliseconds for 1 million rows. The lock is acquired and released almost instantly because PostgreSQL does not rewrite the table.

```sql
-- Verify the column exists with the default
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
\q
```

---

## Step 4: CREATE INDEX CONCURRENTLY

Creating an index on a large table normally acquires a `SHARE` lock, which blocks all writes for the duration of the index build. On a 1M row table this might take seconds - on a 100M row table, it can take minutes or hours.

`CREATE INDEX CONCURRENTLY` builds the index without blocking writes. It takes longer but does not lock the table for writes.

**On your Mac terminal:**

```bash
psql -U postgres -d zerodt_lab
```

```sql
\timing on

-- Standard index (blocks writes during build)
CREATE INDEX idx_customers_email ON customers (email);
```

Expected output (yours will differ):
```
CREATE INDEX
Time: 856.123 ms
```

```sql
DROP INDEX idx_customers_email;

-- Concurrent index (allows writes during build)
CREATE INDEX CONCURRENTLY idx_customers_email ON customers (email);
```

Expected output (yours will differ):
```
CREATE INDEX
Time: 1423.456 ms
```

The concurrent version takes longer but allows all reads and writes while it builds.

```sql
\timing off
```

**Key rules for CREATE INDEX CONCURRENTLY:**

1. It cannot run inside a transaction block. If your migration tool wraps everything in a transaction, you need to disable that.
2. If it fails halfway, it leaves an `INVALID` index behind. Check with:

```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE tablename = 'customers' AND indexname LIKE 'idx_%';
```

3. In Flyway, add this to your migration file to disable transactions:

```sql
-- flyway:executeInTransaction=false

CREATE INDEX CONCURRENTLY idx_customers_email ON customers (email);
```

```sql
\q
```

---

## Step 5: Adding Constraints Safely

Adding a `NOT NULL` constraint or `CHECK` constraint normally scans the entire table while holding a lock. The safe pattern uses two steps:

### Step 5a: Add the Constraint as NOT VALID

```bash
psql -U postgres -d zerodt_lab
```

```sql
\timing on

-- Add a CHECK constraint without validating existing rows
-- This only acquires a brief ACCESS EXCLUSIVE lock
ALTER TABLE customers ADD CONSTRAINT chk_email_not_empty
    CHECK (email IS NOT NULL AND email <> '') NOT VALID;
```

Expected output (yours will differ):
```
ALTER TABLE
Time: 2.345 ms
```

The `NOT VALID` flag means PostgreSQL adds the constraint to the catalog (enforced for new/updated rows) but does not scan existing rows. This is fast.

### Step 5b: Validate the Constraint Separately

```sql
-- Validate scans all existing rows but uses a weaker lock
-- This allows reads AND writes while scanning
ALTER TABLE customers VALIDATE CONSTRAINT chk_email_not_empty;
```

Expected output (yours will differ):
```
ALTER TABLE
Time: 345.678 ms
```

The validation scan takes longer but uses a `SHARE UPDATE EXCLUSIVE` lock, which allows concurrent reads and writes. The table is fully available during the scan.

```sql
\timing off
\q
```

---

## Step 6: Monitor Long-Running Index Operations

PostgreSQL provides progress monitoring for index creation via `pg_stat_progress_create_index`.

Open two terminal windows. In the first terminal, create a large index:

**Terminal 1:**

```bash
psql -U postgres -d zerodt_lab -c "CREATE INDEX CONCURRENTLY idx_customers_name ON customers (name);"
```

**Terminal 2 (while Terminal 1 is running):**

```bash
psql -U postgres -d zerodt_lab -c "
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
 building index: scanning table |        8334 |        4521 |     54.2
```

The phases progress through:
1. `initializing`
2. `building index: scanning table`
3. `building index: sorting live tuples`
4. `building index: loading tuples in tree`
5. `waiting for writers before marking live`

**DBA Analogy:** This is like `pg_stat_progress_vacuum` - you can monitor exactly where a long-running operation stands instead of wondering "is it still going?"

---

## Step 7: The Expand-Contract Pattern in Practice

Let's implement a full expand-contract migration. Scenario: you need to split the `name` column into `first_name` and `last_name`.

### Migration V6: Expand - Add New Columns

```bash
vi ~/dba-labs/zero-downtime/V6__add_name_columns.sql
```

```sql
-- Phase 1: EXPAND - add new columns alongside the old one
-- This is fast on PG 11+ because DEFAULT is stored in catalog
ALTER TABLE customers ADD COLUMN first_name VARCHAR(50);
ALTER TABLE customers ADD COLUMN last_name VARCHAR(50);
```

### Migration V7: Migrate - Backfill Data in Batches

```bash
vi ~/dba-labs/zero-downtime/V7__backfill_name_columns.sql
```

```sql
-- Phase 2: MIGRATE - backfill data in batches to avoid long locks
-- This runs in batches of 10,000 rows to minimize lock duration

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
            last_name = split_part(name, ' ', 2)
        WHERE customer_id IN (
            SELECT customer_id
            FROM customers
            WHERE first_name IS NULL
            LIMIT batch_size
        );

        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        total_updated := total_updated + rows_updated;

        -- Commit-like behavior: each UPDATE is its own statement
        RAISE NOTICE 'Updated % rows (total: %)', rows_updated, total_updated;

        -- Brief pause to let other transactions through
        PERFORM pg_sleep(0.1);
    END LOOP;

    RAISE NOTICE 'Backfill complete. Total rows updated: %', total_updated;
END $$;
```

### Migration V8: Add Constraints

```bash
vi ~/dba-labs/zero-downtime/V8__add_name_constraints.sql
```

```sql
-- Add NOT NULL constraints using the two-step safe pattern
ALTER TABLE customers ADD CONSTRAINT chk_first_name_not_null
    CHECK (first_name IS NOT NULL) NOT VALID;

ALTER TABLE customers VALIDATE CONSTRAINT chk_first_name_not_null;

ALTER TABLE customers ADD CONSTRAINT chk_last_name_not_null
    CHECK (last_name IS NOT NULL) NOT VALID;

ALTER TABLE customers VALIDATE CONSTRAINT chk_last_name_not_null;
```

### Migration V9: Contract - Drop the Old Column

```bash
vi ~/dba-labs/zero-downtime/V9__drop_old_name_column.sql
```

```sql
-- Phase 3: CONTRACT - remove old column
-- Only run this AFTER all application code has been updated to use first_name/last_name
ALTER TABLE customers DROP COLUMN name;
```

**Important:** Do not deploy V9 until the application has been fully updated. The expand-contract pattern gives you a window where both old and new columns exist. Deploy V6-V8, update the application, verify everything works, THEN deploy V9.

---

## Step 8: Run the Migration Sequence

**On your Mac terminal:**

```bash
psql -U postgres -d zerodt_lab -f ~/dba-labs/zero-downtime/V6__add_name_columns.sql
```

Expected output:
```
ALTER TABLE
ALTER TABLE
```

```bash
psql -U postgres -d zerodt_lab -f ~/dba-labs/zero-downtime/V7__backfill_name_columns.sql
```

Expected output (yours will differ):
```
NOTICE:  Updated 10000 rows (total: 10000)
NOTICE:  Updated 10000 rows (total: 20000)
...
NOTICE:  Updated 10000 rows (total: 1000000)
NOTICE:  Updated 0 rows (total: 1000000)
NOTICE:  Backfill complete. Total rows updated: 1000000
DO
```

Verify the backfill:

```bash
psql -U postgres -d zerodt_lab -c "SELECT customer_id, name, first_name, last_name FROM customers LIMIT 5;"
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

## Step 9: Feature Flags for Database Changes

Feature flags allow you to control which version of a database query the application uses, independent of deployment.

The workflow:

1. Deploy migration V6 (add new columns) - flag OFF, app uses old column
2. Backfill data (V7, V8)
3. Turn flag ON for 10% of traffic - app uses new columns
4. Monitor for errors
5. Turn flag ON for 100% of traffic
6. Deploy V9 (drop old column)

This decouples schema changes from application releases. You can roll back the application change (turn flag OFF) without rolling back the schema change.

**DBA Analogy:** This is like switching between read replicas and the primary for read traffic - you gradually shift traffic to the new path and can quickly shift it back if there are problems.

---

## Step 10: Rollback Strategies

### Forward-Only (Recommended)

If migration V5 breaks something, you write V6 to fix it:

```sql
-- V5__add_bad_constraint.sql (the broken migration)
ALTER TABLE customers ADD CONSTRAINT chk_email_format
    CHECK (email ~ '^[^@]+@[^@]+\.[^@]+$');
-- This rejects valid emails like user@localhost

-- V6__fix_email_constraint.sql (the fix)
ALTER TABLE customers DROP CONSTRAINT chk_email_format;
ALTER TABLE customers ADD CONSTRAINT chk_email_format
    CHECK (email ~ '^.+@.+$');
```

This approach:
- Preserves a clear audit trail
- Does not require special tooling
- Works with Flyway Community Edition

### Pre-Deploy Snapshots

Before running migrations on production, take a snapshot:

```sql
-- Create a backup of the table before migration
CREATE TABLE customers_backup_20260609 AS SELECT * FROM customers;
```

If the migration fails, you have a point-in-time copy.

### Transaction Wrapping

For migrations that do not use CONCURRENTLY operations, wrap them in a transaction:

```sql
BEGIN;
ALTER TABLE customers ADD COLUMN phone VARCHAR(20);
-- Test that the application works
-- If not: ROLLBACK;
-- If yes: COMMIT;
COMMIT;
```

**DBA Analogy:** This is your classic `BEGIN; ... ROLLBACK;` testing pattern, but formalized into the deployment process.

---

## Step 11: Testing Migration Speed

Before running a migration on production, test it on a copy of your production data:

```bash
psql -U postgres -c "CREATE DATABASE zerodt_lab_test TEMPLATE zerodt_lab;"
```

Run the migration with timing:

```bash
psql -U postgres -d zerodt_lab_test -c "\timing on" -f ~/dba-labs/zero-downtime/V8__add_name_constraints.sql
```

This tells you:
- How long the migration will take
- Whether it will lock the table for an acceptable duration
- Whether the migration completes without errors

For production tables with billions of rows, test on a copy with production-scale data. A migration that takes 2ms on a 1K row dev table might take 20 minutes on a 100M row production table.

---

## Step 12: Lock Timeout Safety Net

Always set a lock timeout when running migrations on production. If the lock cannot be acquired within the timeout, the migration aborts instead of blocking the lock queue:

```sql
-- Set a 5-second lock timeout
SET lock_timeout = '5s';

-- This will fail if it cannot get the lock within 5 seconds
ALTER TABLE customers ADD COLUMN phone VARCHAR(20);
```

If the lock times out:
```
ERROR:  canceling statement due to lock timeout
```

This prevents the cascading lock queue problem described at the beginning of this guide. Better to fail fast and retry later than to block all queries for minutes.

**Add this to every production migration file:**

```sql
SET lock_timeout = '5s';
SET statement_timeout = '300s';
```

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Lock levels | ALTER TABLE acquires ACCESS EXCLUSIVE - blocks everything |
| Lock queue cascade | Pending locks block all subsequent queries on the table |
| Expand-contract pattern | Add new, migrate data, remove old - three separate migrations |
| CREATE INDEX CONCURRENTLY | Builds indexes without blocking writes (requires `executeInTransaction=false`) |
| PG 11+ ADD COLUMN DEFAULT | Nearly instant - no table rewrite for adding columns with defaults |
| NOT VALID constraints | Add constraint without scanning - validate separately with weaker lock |
| Batched backfills | Update data in batches (10K rows) to minimize lock duration |
| pg_stat_progress_create_index | Monitor long-running index builds |
| Feature flags | Decouple schema changes from application code changes |
| Forward-only rollback | Fix broken migrations with a new migration, not an undo |
| lock_timeout | Fail fast if locks cannot be acquired - prevent queue buildup |
| Testing on copies | Always test migration speed on production-scale data first |

---

**Next:** BUILD 04 - Advanced Migration Tools - compare Flyway with Liquibase, Atlas, and Bytebase.
