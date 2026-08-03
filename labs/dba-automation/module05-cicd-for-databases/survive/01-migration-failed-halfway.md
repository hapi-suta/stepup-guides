# SURVIVE 01: The Migration That Failed Halfway

**Module 05: CI/CD for Database Changes**
**Difficulty: Medium**
**Estimated Time: 30 minutes**

---

## The Scenario

It is 2:15 PM on a Wednesday. You deployed a migration to production that was supposed to:

1. Add a `loyalty_tier` column to the `customers` table
2. Backfill all 2 million rows with a tier based on their order history
3. Add a NOT NULL constraint after the backfill

The migration failed after step 1 and partway through step 2. The column was added, 800,000 of 2 million rows were backfilled, and the remaining 1.2 million rows have NULL values. The NOT NULL constraint was never applied.

The application is running. It does not reference `loyalty_tier` yet (the feature flag is off), so nothing is broken - yet. But the migration is recorded as "failed" in `flyway_schema_history`, and the next deployment is blocked.

---

## Setup - Reproduce the Problem

Run these commands to create the scenario on your local machine.

**On your Mac terminal:**

```bash
psql -U postgres -c "DROP DATABASE IF EXISTS survive_migration;"
psql -U postgres -c "CREATE DATABASE survive_migration;"
```

```bash
psql -U postgres -d survive_migration -c "
-- Create the table with existing data
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    total_orders INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Insert 2 million rows
INSERT INTO customers (name, email, total_orders)
SELECT
    'Customer ' || i,
    'customer' || i || '@example.com',
    (random() * 50)::int
FROM generate_series(1, 2000000) AS i;

-- Simulate the partially-applied migration:
-- Column was added
ALTER TABLE customers ADD COLUMN loyalty_tier VARCHAR(20);

-- Only 800,000 rows were backfilled
UPDATE customers
SET loyalty_tier = CASE
    WHEN total_orders >= 20 THEN 'gold'
    WHEN total_orders >= 10 THEN 'silver'
    ELSE 'bronze'
END
WHERE customer_id <= 800000;

-- Simulate Flyway's failed migration record
CREATE TABLE IF NOT EXISTS flyway_schema_history (
    installed_rank INTEGER PRIMARY KEY,
    version VARCHAR(50),
    description VARCHAR(200),
    type VARCHAR(20),
    script VARCHAR(1000),
    checksum INTEGER,
    installed_by VARCHAR(100),
    installed_on TIMESTAMPTZ DEFAULT now(),
    execution_time INTEGER,
    success BOOLEAN
);

INSERT INTO flyway_schema_history VALUES
(1, '1', 'create customers', 'SQL', 'V1__create_customers.sql', 12345, 'postgres', now() - interval '30 days', 150, true),
(2, '2', 'add loyalty tier', 'SQL', 'V2__add_loyalty_tier.sql', 67890, 'postgres', now(), 45000, false);
"
```

---

## Your Mission

You need to:

1. **Assess the current state** - How many rows are backfilled? How many are NULL?
2. **Decide: roll forward or roll back?** - Justify your decision.
3. **Fix the state** - Complete the backfill or undo the change.
4. **Fix Flyway's history** - Unblock future deployments.
5. **Write a runbook** - Document what happened and how you fixed it, so anyone can follow this process next time.

---

## Investigation Queries

Start by understanding what you are dealing with:

```sql
-- How many rows total?
SELECT count(*) FROM customers;

-- How many are backfilled vs NULL?
SELECT
    count(*) FILTER (WHERE loyalty_tier IS NOT NULL) AS backfilled,
    count(*) FILTER (WHERE loyalty_tier IS NULL) AS remaining
FROM customers;

-- What does Flyway think?
SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank;

-- Is anything else using this column?
SELECT * FROM pg_depend WHERE objid = (
    SELECT attnum FROM pg_attribute
    WHERE attrelid = 'customers'::regclass AND attname = 'loyalty_tier'
);
```

---

## Decision Framework

### Option A: Roll Forward (complete the migration)

**Pros:**
- The column exists and 800K rows are already correct
- Application code is ready (behind a feature flag)
- Less work than undoing everything

**Cons:**
- Need to backfill 1.2M more rows
- Need to add the NOT NULL constraint
- Migration history needs repair

### Option B: Roll Back (undo everything)

**Pros:**
- Clean slate - as if the migration never happened
- Can re-run the migration properly later

**Cons:**
- Waste the backfill work already done
- Need to drop the column
- Need to repair migration history
- Must re-deploy the migration from scratch

### The Right Choice

For this scenario, **roll forward** is almost always the right answer because:
- The column exists and is not hurting anything
- 40% of data is already correct
- Rolling back and redoing wastes time and carries its own risks

---

## Resolution Steps

### Step 1: Complete the Backfill

Complete the remaining rows in batches:

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

### Step 2: Verify the Backfill

```sql
SELECT count(*) FILTER (WHERE loyalty_tier IS NULL) AS still_null FROM customers;
-- Should return 0
```

### Step 3: Add the NOT NULL Constraint Safely

```sql
ALTER TABLE customers ADD CONSTRAINT chk_loyalty_tier_nn
    CHECK (loyalty_tier IS NOT NULL) NOT VALID;

ALTER TABLE customers VALIDATE CONSTRAINT chk_loyalty_tier_nn;
```

### Step 4: Repair Flyway History

Remove the failed entry and mark it as a new successful migration:

```sql
-- Delete the failed record
DELETE FROM flyway_schema_history WHERE version = '2' AND success = false;
```

Now you have two options:

**Option A:** Re-run `flyway migrate` with the corrected migration file (update checksum)

**Option B:** Manually insert a success record:

```sql
INSERT INTO flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success)
VALUES (2, '2', 'add loyalty tier', 'SQL', 'V2__add_loyalty_tier.sql', 67890, 'postgres', now(), 60000, true);
```

Alternatively, use `flyway repair` which cleans up failed entries:

```bash
flyway -configFiles=flyway.conf repair
```

### Step 5: Verify Everything

```sql
-- All rows should have loyalty_tier
SELECT loyalty_tier, count(*) FROM customers GROUP BY loyalty_tier ORDER BY count(*) DESC;

-- Flyway should show all success
SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank;

-- Constraint should be validated
SELECT conname, convalidated FROM pg_constraint
WHERE conrelid = 'customers'::regclass AND conname = 'chk_loyalty_tier_nn';
```

---

## Validation Checklist

- [ ] All 2,000,000 rows have a non-NULL `loyalty_tier`
- [ ] The loyalty_tier distribution makes sense (based on total_orders)
- [ ] Flyway history shows all migrations as successful
- [ ] `flyway validate` passes
- [ ] `flyway info` shows no pending or failed migrations
- [ ] The NOT NULL constraint (or CHECK equivalent) is in place and validated

---

## Lessons Learned

1. **Migrations that do DDL + DML should be split** - one migration for the column, another for the backfill, a third for the constraint.
2. **Batched backfills are essential** - a single UPDATE on 2M rows can time out or get killed.
3. **flyway repair is your friend** - it cleans up failed migration entries so you can retry.
4. **Always have a decision framework** - roll forward vs roll back depends on how much work was done and whether the partial state is harmful.
