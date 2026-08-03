# USE 03: Rollback Strategy Exercise

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster

---

## Objective

Practice three rollback strategies on realistic failure scenarios. You will encounter a broken migration, decide whether to roll forward or roll back, and execute the recovery.

---

## Setup

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "CREATE DATABASE rollback_exercise;"
```

Create the base schema:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d rollback_exercise -c "
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    email       VARCHAR(255) UNIQUE,
    tier        VARCHAR(20) DEFAULT 'free',
    created_at  TIMESTAMPTZ DEFAULT now()
);

INSERT INTO customers (name, email, tier)
SELECT
    'Customer ' || i,
    'cust' || i || '@example.com',
    CASE (i % 3) WHEN 0 THEN 'free' WHEN 1 THEN 'pro' ELSE 'enterprise' END
FROM generate_series(1, 200000) AS i;
"
```

---

## Scenario 1: Forward-Only Recovery

### The Problem

You deployed a migration that adds a NOT NULL constraint to a column that has NULL values:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d rollback_exercise -c "
-- Simulate: some customers have no email
UPDATE customers SET email = NULL WHERE customer_id % 7 = 0;
"
```

Now try to add the NOT NULL constraint:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d rollback_exercise -c "
ALTER TABLE customers ALTER COLUMN email SET NOT NULL;
"
```

This fails because rows with NULL email exist.

### Your Task

1. Count how many rows have NULL email
2. Decide on a fix strategy:
   - Option A: Backfill the NULLs with a default value, then add the constraint
   - Option B: Add a CHECK constraint with NOT VALID, backfill, then validate
3. Write and execute the forward fix as a migration
4. Verify the constraint is in place and all rows comply

### Acceptance Criteria

<details>
<summary>Click to expand</summary>

- [ ] All NULL emails are populated with a valid value
- [ ] A NOT NULL constraint (or CHECK equivalent) is active and validated
- [ ] No rows violate the constraint
- [ ] The fix was done without dropping any data

</details>

---

## Scenario 2: Transaction-Based Rollback

### The Problem

You need to test a risky migration before committing. The migration renames a column and changes its type.

### Your Task

1. Start a transaction with `BEGIN;`
2. Add a new column `full_name VARCHAR(200)`
3. Backfill `full_name` from `name` (just the first 100 rows to test)
4. Check the results with a SELECT
5. Roll back with `ROLLBACK;`
6. Verify the column does not exist after rollback

Then, when you are satisfied the migration works:

7. Run it again without `ROLLBACK` - use `COMMIT` instead
8. Verify the column exists and is populated

### Acceptance Criteria

<details>
<summary>Click to expand</summary>

- [ ] Transaction rollback cleanly undoes the column addition
- [ ] After COMMIT, the column exists and is populated
- [ ] You tested before committing

</details>

---

## Scenario 3: Flyway Repair Recovery

### The Problem

A Flyway migration failed partway through, leaving the database in an inconsistent state.

### Setup

```bash
mkdir -p ~/dba-labs/use-rollback-repair/sql
```

```bash
cd ~/dba-labs/use-rollback-repair
```

Create a flyway.conf:

```bash
vi flyway.conf
```

```properties
flyway.url=jdbc:postgresql://YOUR_AURORA_ENDPOINT:5432/rollback_exercise
flyway.user=postgres
flyway.password=YOUR_PASSWORD
flyway.locations=filesystem:./sql
flyway.cleanDisabled=true
```

Baseline the existing database:

```bash
flyway -configFiles=flyway.conf baseline -baselineVersion=0
```

Create a migration that will partially fail:

```bash
vi sql/V1__add_columns_and_break.sql
```

```sql
SET lock_timeout = '5s';

-- This will succeed
ALTER TABLE customers ADD COLUMN phone VARCHAR(20);

-- This will fail (table does not exist)
ALTER TABLE addresses ADD COLUMN city VARCHAR(100);
```

### Your Task

1. Run `flyway migrate` and observe the failure
2. Check the database state - did the `phone` column get added?
3. Check `flyway_schema_history` for the failed entry
4. Fix the migration file (remove the broken line)
5. Run `flyway repair` to clean up the failed entry
6. Run `flyway migrate` again
7. Verify everything is clean with `flyway validate`

### Acceptance Criteria

<details>
<summary>Click to expand</summary>

- [ ] You understand why PostgreSQL rolled back the entire migration (transactional DDL)
- [ ] `flyway repair` cleaned up the failed entry
- [ ] The fixed migration applies cleanly
- [ ] `flyway validate` passes
- [ ] `flyway info` shows all migrations as Success

</details>

---

## Clean Up

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "DROP DATABASE IF EXISTS rollback_exercise;"
```

---

## Reflection Questions

After completing all three scenarios, answer these:

1. Why is forward-only the preferred strategy in most cases?
2. When is transaction-based rollback NOT possible?
3. What does `flyway repair` actually do to the `flyway_schema_history` table?
4. If a migration partially applied (DDL succeeded but DML failed), which strategy would you use?
5. How does Aurora backtrack differ from `flyway repair`?

<details>
<summary>Click for answers</summary>

1. Forward-only preserves audit trail, avoids data loss, and works with all Flyway editions.
2. Transaction rollback is not possible for `CREATE INDEX CONCURRENTLY` or any operation that requires `executeInTransaction=false`.
3. `flyway repair` deletes rows with `success = false` from `flyway_schema_history` and realigns checksums.
4. Roll forward - the DDL already exists, so write a new migration to complete the DML.
5. Aurora backtrack rewinds the entire database to a point in time. `flyway repair` only fixes the migration history table - it does not undo DDL or DML.

</details>
