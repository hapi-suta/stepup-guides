# SURVIVE 02: Rollback Failure

**Module 08: CI/CD for Database Changes**
**Difficulty:** Medium-Hard
**Estimated Time:** 30-45 minutes
**Cluster:** devops-lab-cluster

---

## The Scenario

It is 3:15 PM on a Wednesday. You deployed a migration to production that was supposed to:

1. Add a `loyalty_tier` column to the `customers` table
2. Backfill all 1,000,000 rows with a tier based on order history
3. Add a NOT NULL constraint after the backfill

The migration crashed after step 1 and partway through step 2. Here is the current state:

- The `loyalty_tier` column exists (step 1 completed)
- 400,000 rows have `loyalty_tier` populated (step 2 partially completed)
- 600,000 rows have `loyalty_tier = NULL` (step 2 did not finish)
- The NOT NULL constraint was never applied (step 3 never ran)
- Flyway shows V2 as `failed` - no new migrations can run

The application is running. It does not reference `loyalty_tier` yet (the feature flag is off), so nothing is broken right now. But the failed Flyway entry blocks all future deployments.

---

## Setup

Run the inject script:

**On your Mac terminal:**

```bash
export AURORA_ENDPOINT=YOUR_AURORA_ENDPOINT
export DB_USER=postgres
```

```bash
chmod +x inject.sh
```

```bash
./inject.sh
```

---

## Your Mission

1. Assess the current state
2. Decide: roll forward or roll back?
3. Complete the fix
4. Repair Flyway history
5. Verify everything

---

## Investigation

### Step 1: Assess the Data State

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d survive_rollback_failure
```

```sql
-- How many rows total?
SELECT count(*) AS total_rows FROM customers;
```

```sql
-- How many are backfilled vs NULL?
SELECT
    count(*) FILTER (WHERE loyalty_tier IS NOT NULL) AS backfilled,
    count(*) FILTER (WHERE loyalty_tier IS NULL)     AS remaining
FROM customers;
```

Expected output:
```
 backfilled | remaining
------------+-----------
     400000 |    600000
```

```sql
-- What does Flyway think?
SELECT version, description, success
FROM flyway_schema_history
ORDER BY installed_rank;
```

Expected output:
```
 version |          description          | success
---------+------------------------------+---------
 1       | create customers             | t
 2       | add loyalty tier and backfill | f
```

### Step 2: Decision - Roll Forward or Roll Back?

**Roll Forward (recommended):**
- The column exists and 400,000 rows are already correct
- The application has a feature flag (not using this column yet)
- Completing the backfill is less work than undoing everything

**Roll Back would mean:**
- Drop the column (losing 400K rows of backfilled data)
- Repair Flyway history
- Re-write and re-deploy the migration later

**Decision: Roll forward.** The partial state is not harmful, and 40% of the work is done.

---

## Resolution

### Step 3: Complete the Backfill

Complete the remaining 600,000 rows using batched updates:

```sql
DO $$
DECLARE
    batch_size INT := 50000;
    rows_updated INT := 1;
    total_updated INT := 0;
BEGIN
    WHILE rows_updated > 0 LOOP
        UPDATE customers
        SET loyalty_tier = CASE
            WHEN total_orders >= 20 THEN 'gold'
            WHEN total_orders >= 10 THEN 'silver'
            ELSE 'bronze'
        END
        WHERE customer_id IN (
            SELECT customer_id FROM customers
            WHERE loyalty_tier IS NULL
            LIMIT batch_size
        );

        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        total_updated := total_updated + rows_updated;
        RAISE NOTICE 'Backfilled % rows (total: %)', rows_updated, total_updated;
        PERFORM pg_sleep(0.1);
    END LOOP;

    RAISE NOTICE 'Backfill complete: % rows total', total_updated;
END $$;
```

- `batch_size := 50000` - updates 50,000 rows at a time.
- `PERFORM pg_sleep(0.1)` - pauses 100ms between batches to let other transactions through.
- The `WHERE loyalty_tier IS NULL` clause ensures we only update rows that were not already backfilled.

Expected output (yours will differ):
```
NOTICE:  Backfilled 50000 rows (total: 50000)
NOTICE:  Backfilled 50000 rows (total: 100000)
...
NOTICE:  Backfilled 50000 rows (total: 600000)
NOTICE:  Backfilled 0 rows (total: 600000)
NOTICE:  Backfill complete: 600000 rows total
```

### Step 4: Verify the Backfill

```sql
SELECT count(*) FILTER (WHERE loyalty_tier IS NULL) AS still_null
FROM customers;
```

Expected output:
```
 still_null
------------
          0
```

Check the distribution:

```sql
SELECT loyalty_tier, count(*)
FROM customers
GROUP BY loyalty_tier
ORDER BY count(*) DESC;
```

### Step 5: Add the NOT NULL Constraint Safely

Use the two-step NOT VALID + VALIDATE pattern:

```sql
SET lock_timeout = '5s';

ALTER TABLE customers ADD CONSTRAINT chk_loyalty_tier_nn
    CHECK (loyalty_tier IS NOT NULL) NOT VALID;
```

- `NOT VALID` adds the constraint without scanning existing rows. Brief lock.

```sql
ALTER TABLE customers VALIDATE CONSTRAINT chk_loyalty_tier_nn;
```

- `VALIDATE CONSTRAINT` scans all rows but uses a weaker lock that allows reads and writes.

### Step 6: Repair Flyway History

Delete the failed entry:

```sql
DELETE FROM flyway_schema_history
WHERE version = '2' AND success = false;
```

Insert a success record:

```sql
INSERT INTO flyway_schema_history
    (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success)
VALUES
    (2, '2', 'add loyalty tier and backfill', 'SQL', 'V2__add_loyalty_tier.sql', 67890, 'postgres', now(), 60000, true);
```

Alternatively, if you have Flyway available, use `flyway repair`:

```bash
flyway -configFiles=flyway.conf repair
```

### Step 7: Verify Everything

```sql
-- All rows should have loyalty_tier
SELECT count(*) FILTER (WHERE loyalty_tier IS NULL) AS nulls FROM customers;
-- Expected: 0

-- Tier distribution should make sense
SELECT loyalty_tier, count(*) FROM customers GROUP BY loyalty_tier;

-- Flyway should show all success
SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank;

-- Constraint should be validated
SELECT conname, convalidated
FROM pg_constraint
WHERE conrelid = 'customers'::regclass
  AND conname = 'chk_loyalty_tier_nn';
```

Expected: `convalidated = true`

```sql
\q
```

---

## Lessons Learned

1. **Split DDL, DML, and constraints into separate migrations** - V2a adds the column, V2b backfills, V2c adds the constraint. If V2b fails, V2a is already committed and you only need to retry V2b.

2. **Batch your backfills** - A single UPDATE on 1M rows can time out or get killed by statement_timeout. Batched updates are resumable.

3. **flyway repair is your friend** - It cleans up failed migration entries so you can fix the file and retry.

4. **Always have a decision framework** - Roll forward vs roll back depends on how much work was done and whether the partial state is harmful.

---

## Validation

Run the validation script:

```bash
chmod +x validate.sh
```

```bash
./validate.sh
```

All checks should show PASS.
